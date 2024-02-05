defmodule RPG do
  @moduledoc """
  GenServer for creating, joining, and interacting with parties
  """

  use GenServer

  alias RPG.GameEngine
  alias RPG.Party

  require Logger

  ### API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{parties: %{}, forming: %{}, refs: %{}}, name: __MODULE__)
  end

  def action_form, do: "<verb> <item> [at <subject> [with <item(s)>]]"

  def help_message do
    """
    Welcome to RPG bot! This is the list of actions you can take. All actions take the form of #{action_form()}.

    Meta verbs:
    - help - display this message
    - join - join a party that's currently forming
    - begin - form a party with the currently joined players

    Game verbs:
    - #{Enum.join(GameEngine.action_verbs(), "\n- ")}
    """
  end

  @doc """
  Process an action on behalf of a player.

  When the action is `"begin"`, the caller will be subscribed to the `rpg:<party_id>` topic. Therefore, in order to
  receive events that aren't a direct result of a player action, the caller must process messages of the form
  `{:rpg, party_id, message}` as they are received and forward them to players.

  NPC events (those not triggered as a direct result of a player action, e.g. an enemy in an engagement takes an action)
  are typically fired off in 1-second intervals. Additional ratelimiting may be needed on the consumer-side depending
  on the frontend.
  """
  def handle_action(_party_id, _member, "help"), do: {:reply, help_message()}

  def handle_action(party_id, member, "join"), do: GenServer.call(__MODULE__, {:join, party_id, member})

  def handle_action(party_id, _member, "begin") do
    case GenServer.call(__MODULE__, {:begin, party_id}) do
      {:ok, message} ->
        Phoenix.PubSub.unsubscribe(RPG.PubSub, "rpg:#{party_id}")
        Phoenix.PubSub.subscribe(RPG.PubSub, "rpg:#{party_id}")
        {:reply, message}

      {:error, message} ->
        {:reply, message}
    end
  end

  def handle_action(party_id, member, action) when not is_nil(action) do
    with {:ok, party_pid} <- GenServer.call(__MODULE__, {:get_party, party_id}),
         {:ok, response} <- Party.handle_action(party_pid, member, action) do
      {:reply, response}
    end
  end

  def kill_party(party_id), do: GenServer.call(__MODULE__, {:kill_party, party_id})

  ### IMPL

  @impl GenServer
  def init(state) do
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:join, party_id, member}, _from, state) when not is_map_key(state.parties, party_id) do
    if member in Map.get(state.forming, party_id, []) do
      {:reply, {:reply, "You are already in the party."}, state}
    else
      state = Map.update!(state, :forming, &Map.update(&1, party_id, [member], fn joining -> [member | joining] end))

      {:reply, {:reply, new_member_reply(member, state.forming[party_id])}, state}
    end
  end

  @impl GenServer
  def handle_call({:join, _party_id, _member}, _from, state) do
    {:reply, {:reply, "You are already in the party."}, state}
  end

  @impl GenServer
  def handle_call({:begin, party_id}, _from, state) when not is_map_key(state.parties, party_id) do
    case Map.pop(state.forming, party_id, :no_forming) do
      {[_ | _] = members, new_forming} ->
        {:ok, party_pid} = DynamicSupervisor.start_child(RPG.PartySupervisor, {Party, {party_id, members}})
        ref = Process.monitor(party_pid)
        {:ok, exposition} = Party.begin(party_pid)

        state = %{
          state
          | parties: Map.put(state.parties, party_id, party_pid),
            forming: new_forming,
            refs: Map.put(state.refs, ref, party_id)
        }

        {:reply, {:ok, "The game has begun...use the $help action to see the full list of actions\n\n#{exposition}"},
         state}

      {[], _} ->
        {:reply, {:error, "Could not begin a party (no one has `join`ed yet!)"}, state}

      {:no_forming, _} ->
        {:reply, {:error, "There is not a party to begin. Try `join`ing one first."}, state}

      {huh?, _} ->
        Logger.error("RPG Got :begin, but something unexpected under state.forming[#{party_id}]: #{inspect(huh?)}")
        {:reply, {:error, "Could not begin a party (unknown reason, check the logs ben)"}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_party, party_id}, _from, state), do: {:reply, Map.fetch(state.parties, party_id), state}

  @impl GenServer
  def handle_call({:kill_party, party_id}, _from, state) do
    {party_pid, parties} = Map.pop(state.parties, party_id)
    DynamicSupervisor.terminate_child(RPG.PartySupervisor, party_pid)
    {:reply, party_pid, %{state | parties: parties}}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _, reason}, state) do
    case Map.pop(state.refs, ref) do
      {nil, _} ->
        {:noreply, state}

      {party_id, refs} ->
        unless reason == :normal do
          Phoenix.PubSub.broadcast(RPG.PubSub, "rpg:#{party_id}", {:rpg, party_id, fatal_error_reply()})
        end

        {:noreply, %{state | parties: Map.delete(state.parties, party_id), refs: refs}}
    end
  end

  defp new_member_reply(new_member, party_members) do
    """
    👋#{new_member} has joined the party, along with #{Enum.join(party_members -- [new_member], ", ")}.

    Once all members have joined, send "begin" to start your journey.
    """
  end

  defp fatal_error_reply do
    "❗(The game encountered a fatal error, and the party will have to be restarted. Sorry for the inconvenience)"
  end
end
