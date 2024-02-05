defmodule RPG.GameEngine do
  @moduledoc """
  The main RPG engine.

  Functions generally take a %Party{} as the first arg, and return an updated struct transformed based on the function.
  """

  import RPG.GameEngine.Character

  alias RPG.GameEngine.Actions
  alias RPG.Party

  require Logger

  # cast
  @action_verbs ~w[approach disengage swing shoot throw drink eat consume examine craft grab continue retreat]
  def action_verbs, do: @action_verbs

  @spec apply_action(map(), String.t(), list()) :: {:ok, new_party :: map(), response :: String.t()}
  def apply_action(%Party{state: :roaming} = party, actor_id, [_verb | _args] = action) do
    do_apply_action(party, actor_id, action)
  end

  def apply_action(%Party{state: :engagement} = party, actor_id, [_verb | _args] = action) do
    case :queue.peek(party.initiative) do
      {:value, ^actor_id} ->
        do_apply_action(party, actor_id, action)

      _not_turn ->
        {:ok, party, "(It's not your turn, #{actor_id})"}
    end
  end

  defp do_apply_action(%Party{state: state} = party, actor_id, [verb | args] = action) do
    case apply(Actions, String.to_existing_atom(verb), [party, actor_id | args]) do
      {:ok, party, response} ->
        party
        |> Map.update!(:action_log, &[{actor_id, action} | &1])
        |> rotate_initiative(state)
        |> case do
          %Party{state: :dead} = new_party ->
            {:ok, new_party, response <> "\nEveryone in the party has died :("}

          %Party{} = new_party ->
            {:ok, new_party, response}
        end

      {:invalid, response} ->
        {:ok, party, response}
    end
  rescue
    e ->
      Logger.warning("an exception was raised while trying to apply the action #{inspect(action)}:")
      Logger.error(Exception.format(:error, e, __STACKTRACE__))

      {:ok, party,
       "(I didn't understand the action, #{inspect(action)}. Please try something else. If this seems like a bug, ping ben he probably did something dumb :^])"}
  end

  def roll(%Range{} = die), do: Enum.random(die)
  def roll(die_sides) when is_integer(die_sides), do: Enum.random(1..die_sides)

  defp rotate_initiative(%Party{state: :roaming} = party, :roaming), do: party
  defp rotate_initiative(%Party{state: :roaming} = party, :engagement), do: %Party{party | initiative: :queue.new()}

  defp rotate_initiative(%Party{state: :engagement} = party, :roaming) do
    # TODO: also take the actor of the last action, and make sure they're last in the new initiative(?)
    initiative =
      party.directory
      |> Map.keys()
      |> Enum.shuffle()
      |> Enum.reduce(:queue.new(), fn actor_id, queue -> :queue.in(actor_id, queue) end)

    %Party{party | initiative: initiative} |> skip_unconscious()
  end

  defp rotate_initiative(%Party{state: :engagement} = party, :engagement) do
    case :queue.out(party.initiative) do
      {{:value, actor_id}, initiative} ->
        %Party{party | initiative: actor_id |> :queue.in(initiative)} |> skip_unconscious()

      {:empty, _initiative} ->
        Logger.warning("rotate_initiative/1: tried to rotate initiative queue, but it's empty")
        party
    end
  end

  defp skip_unconscious(%Party{} = party) do
    party.initiative
    |> :queue.to_list()
    |> Enum.split_while(&(not is_conscious(party.directory[&1])))
    |> case do
      {[], _no_one_to_skip} ->
        party

      {_everyone_unconscious, []} ->
        %Party{party | state: :dead}

      {unconscious, [_ | _] = at_least_one_conscious} ->
        %Party{party | initiative: :queue.from_list(at_least_one_conscious ++ unconscious)}
    end
  end
end
