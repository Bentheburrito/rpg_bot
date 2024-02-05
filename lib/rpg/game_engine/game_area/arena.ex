defmodule RPG.GameEngine.GameArea.Arena do
  alias RPG.GameEngine.Character
  alias RPG.GameEngine.Item.Common
  alias RPG.GameEngine.RNG
  alias RPG.Party

  @behaviour RPG.GameEngine.GameArea

  @bronze_short_sword "bronze short sword"

  @impl RPG.GameEngine.GameArea
  def init_area() do
    goblins =
      Map.new(1..4, fn id ->
        {"goblin_#{id}",
         Character.new(
           "Goblin #{RNG.random_name()}",
           hit_points: {6, 6},
           armor: Common.light_leather_armor(),
           inventory: %{@bronze_short_sword => Common.bronze_short_sword()}
         )}
      end)

    {goblins, :engagement, "A group of #{map_size(goblins)} goblins has jumped you! Prepare to fight!"}
  end

  @impl RPG.GameEngine.GameArea
  def next_area(), do: {:ok, RPG.GameEngine.GameArea.Arena}

  @impl RPG.GameEngine.GameArea
  def prev_area() do
    # TODO: lobby area or something to exit the arena
    :none
  end

  @impl RPG.GameEngine.GameArea
  def npc_action(%Party{} = party, "goblin_" <> _num = id) do
    # the goblin's proximity leader is the same as another character, and that character is controlled by a player -
    # in other words, this finds players the goblin is close enough to to attack
    near_by_players = fn {_, leader} -> leader == party.proximity_map[id] and leader in party.member_ids end

    case Enum.find(party.proximity_map, near_by_players) do
      # not close to any players - approach one
      nil ->
        {:ok, "approach #{Enum.random(party.member_ids)}"}

      {near_by_player_id, _} ->
        {:ok, "swing #{@bronze_short_sword} at #{near_by_player_id}"}
    end
  end
end
