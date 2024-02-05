defmodule RPG.Party do
  @moduledoc """
  A group of players, aka a party.
  """
  use GenServer, restart: :temporary

  import RPG.GameEngine.Character

  alias RPG.GameEngine.RNG
  alias Phoenix.PubSub
  alias RPG.GameEngine.Item.Common
  alias RPG.GameEngine.Character
  alias RPG.GameEngine
  alias RPG.GameEngine.Item
  alias RPG.Party, as: State

  require Logger

  @type states :: :engagement | :roaming | :dead

  @type t() :: %__MODULE__{
          area: module(),
          action_log: [{String.t(), list()}],
          directory: map(),
          id: nil,
          initiative: :queue.queue(),
          member_ids: MapSet.t(),
          proximity_map: map(),
          state: states()
        }
  @enforce_keys :id
  defstruct action_log: [],
            # TODO: should start in generic lobby
            area: RPG.GameEngine.GameArea.Arena.Lobby,
            directory: Map.new(),
            id: nil,
            initiative: :queue.new(),
            member_ids: MapSet.new(),
            proximity_map: Map.new(),
            state: :roaming

  ### API

  def start_link({id, members}) when is_list(members) do
    GenServer.start_link(__MODULE__, %State{id: id, member_ids: members})
  end

  def begin(party) do
    GenServer.call(party, :begin)
  end

  # meta actions at the party level - don't really belong in GameEngine
  def handle_action(party, _member, "status"), do: {:ok, GenServer.call(party, :get_status)}
  def handle_action(party, member, "inventory"), do: {:ok, GenServer.call(party, {:inventory_for, member})}

  def handle_action(party, member, action) when is_binary(action) do
    case parse_action(action) do
      {:ok, action} ->
        handle_action(party, member, action)

      :invalid_action ->
        :invalid_action
    end
  end

  def handle_action(party, member, action) when is_list(action) do
    GenServer.call(party, {:action, member, action})
  end

  ### IMPL

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:begin, _from, %State{} = state) do
    # TODO: ask users to create their characters
    directory =
      Map.new(state.member_ids, fn id ->
        name = RNG.random_name()

        character =
          Character.new(name,
            armor: Common.heavy_chainmail_armor(),
            inventory: %{
              "iron sword" => Common.iron_long_sword(),
              "healing potion" => %Item{Common.minor_healing_potion() | quantity: 5}
            }
          )

        {id, character}
      end)

    {npc_map, next_state, exposition} = state.area.init_area()

    directory = Map.merge(npc_map, directory)
    prox_map = Map.new(directory, fn {key, _} -> {key, key} end)

    {:reply, {:ok, exposition}, %State{state | state: next_state, directory: directory, proximity_map: prox_map}}
  end

  @impl GenServer
  def handle_call({:action, member, action}, _from, state) do
    # TODO: on terminate, save characters to DB
    case apply_action(state, member, action) do
      {:ok, %State{} = state, response} -> {:reply, {:ok, response}, state}
      {:terminate, %State{} = state, response} -> {:stop, :normal, {:ok, response}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, %State{} = state) do
    characters =
      for {id, %Character{} = char} <- state.directory do
        health =
          cond do
            id in state.member_ids -> "#{hp_to_string(char)}HP"
            not is_conscious(char) -> "*incapacitated*"
            cur_hp(char) < max_hp(char) -> "*damaged, HP unknown*"
            :else -> "*HP unknown*"
          end

        "#{char} (#{id}) #{health}"
      end

    groups = Enum.group_by(state.proximity_map, fn {_, leader} -> leader end, fn {id, _} -> id end)

    {:reply,
     """
     ##### Characters
     - #{Enum.join(characters, "\n- ")}

     ##### Groups (Characters in melee range)

     - #{Enum.map_join(groups, "\n- ", fn {_leader, id_list} -> Enum.map_join(id_list, ", ", &"#{state.directory[&1]} (#{&1})") end)}

     *use the `approach` and `disengage` actions to join or leave groups*
     """, state}
  end

  @impl GenServer
  def handle_call({:inventory_for, member}, _from, %State{} = state) do
    char = state.directory[member]

    {:reply,
     """
     ##### #{char}'s inventory (#{inventory_weight(char)}/#{char.inven_cap}kg total)

     #{Enum.map_join(char.inventory, "\n\n", fn {friendly_name, item} -> "#{friendly_name} => #{inspect(item)}" end)}

     Refer to each item by the phrase before the arrow (=>) when performing an action.
     E.g. "$swing iron sword" instead of "$swing Iron Long Sword"
     """, state}
  end

  @impl GenServer
  def handle_info(:npc_action, %State{} = state) do
    # TODO: refactor this into helper fxns to avoid complex else clauses in this with
    with {:value, npc_id} <- :queue.peek(state.initiative),
         {:npc?, true} <- {:npc?, npc_id not in state.member_ids},
         {:ok, npc_action} <- state.area.npc_action(state, npc_id),
         {{:ok, npc_action}, _} <- {parse_action(npc_action), npc_action} do
      {result, %State{} = state, response} = apply_action(state, npc_id, npc_action)
      PubSub.broadcast(RPG.PubSub, "rpg:#{state.id}", {:rpg, state.id, response})

      case result do
        :ok -> {:noreply, state}
        :terminate -> {:stop, :normal, state}
      end
    else
      # this NPC doesn't do anything special this turn, ignore them
      :none ->
        {:noreply, state}

      {:npc?, false} ->
        Logger.warning(
          "Received :npc_action, but the next character is a player character...something's wrong: #{inspect(state)}"
        )

      :empty ->
        Logger.warning(
          "Received :npc_action, but there was nothing to peek in state.initiative...something's wrong: #{inspect(state)}"
        )

        {:noreply, state}

      {:invalid_action, action} ->
        Logger.warning(
          "Received :npc_action, but the action (#{inspect(action)}) could not be parsed...something's wrong: #{inspect(state)}"
        )

        {:noreply, state}
    end
  end

  defp parse_action(action) when is_list(action), do: {:ok, action}

  @action_verbs GameEngine.action_verbs()
  defp parse_action(action) do
    with [verb_item_str | optional_modifiers] <- String.split(action, [" at ", " with "]),
         [verb | _] = verb_item when verb in @action_verbs <- String.split(verb_item_str, " ", parts: 2) do
      {:ok, Enum.map(verb_item ++ optional_modifiers, &String.downcase/1)}
    else
      _ -> :invalid_action
    end
  end

  defp apply_action(%State{} = state, member, action) do
    {:ok, %State{} = state, response} = GameEngine.apply_action(state, member, action)

    cond do
      all_ids_conscious?(state.member_ids, state.directory) ->
        {:terminate, state, response <> "\nAll party members have perished :( the party has been disbanded"}

      # TODO: refactor this to work with non-hostile NPCs
      state.state == :engagement and all_enemy_ids_dead?(state) ->
        {:ok, %State{state | state: :roaming}, response <> "\nAll enemies in this area have been vanquished! 🎉"}

      :else ->
        maybe_notify_next_turn(state)

        {:ok, state, response}
    end
  end

  defp all_enemy_ids_dead?(%State{} = state) do
    state.directory |> Map.keys() |> Stream.reject(&(&1 in state.member_ids)) |> all_ids_conscious?(state.directory)
  end

  defp maybe_notify_next_turn(%State{} = state) do
    # after a character makes an action in an engagement, check if the next turn is for an NPC. If so, queue up their
    # turn, but defer it by 1 second (helps to reduce spam if frontends don't do any kind of ratelimiting)
    with :engagement <- state.state,
         {:value, next_actor_id} <- :queue.peek(state.initiative),
         {:npc_id?, _, true} <- {:npc_id?, next_actor_id, next_actor_id not in state.member_ids} do
      Process.send_after(self(), :npc_action, 1000)
    else
      {:npc_id?, player_actor_id, false} ->
        Task.start(fn ->
          Process.sleep(1000)
          PubSub.broadcast(RPG.PubSub, "rpg:#{state.id}", {:rpg, state.id, "(It's now #{player_actor_id}'s turn)"})
        end)

      _ ->
        nil
    end
  end

  defp all_ids_conscious?(ids, directory), do: Enum.all?(ids, &(not is_conscious(directory[&1])))
end
