defmodule RPG.GameEngine.RNG do
  @abilities [:strength, :dexterity, :charisma, :intelligence, :constitution, :wisdom]

  def ability_scores(), do: Map.new(@abilities, &{&1, Enum.random(3..18)})

  # lol
  def random_name, do: Enum.random(~w"Te Pe Ga Ha Je Ke La Ma Ba Ca") <> "rry"
end
