defmodule RPG.GameEngine.Character do
  @moduledoc """
  A character in the game world.
  """

  alias RPG.GameEngine.Item
  alias RPG.GameEngine
  alias RPG.GameEngine.Item.Armor
  alias RPG.GameEngine.Item.Weapon
  alias RPG.GameEngine.Character

  @abilities [:strength, :dexterity, :charisma, :intelligence, :constitution, :wisdom]
  @type ability :: :strength | :dexterity | :charisma | :intelligence | :constitution | :wisdom

  # TODO: xp field
  @enforce_keys [:ability_scores, :name]
  defstruct ability_scores: nil,
            armor: nil,
            hit_points: {15, 15},
            inventory: %{},
            inven_cap: 80,
            name: nil

  def new(name, other_fields) do
    struct!(%Character{name: name, ability_scores: GameEngine.RNG.ability_scores()}, other_fields)
  end

  def ability_modifier(%Character{} = c, ability) when ability in @abilities do
    score = c.ability_scores[ability]
    floor((score - 10) / 2)
  end

  def armor_class(%Character{armor: %Item{type: %Armor{armor_class: ac}}}), do: ac
  def armor_class(%Character{armor: nil}), do: 2

  def subtract_hp(%Character{hit_points: {cur_hp, max_hp}} = c, hp),
    do: %Character{c | hit_points: {cur_hp - max(hp, 0), max_hp}}

  def add_hp(%Character{hit_points: {cur_hp, max_hp}} = c, hp),
    do: %Character{c | hit_points: {cur_hp + min(hp, max_hp - cur_hp), max_hp}}

  def cur_hp(%Character{hit_points: {cur_hp, _}}), do: cur_hp
  def max_hp(%Character{hit_points: {_, max_hp}}), do: max_hp
  def hp_to_string(%Character{} = c), do: "#{cur_hp(c)}/#{max_hp(c)}"

  defguard is_conscious(character) when elem(character.hit_points, 0) > 0

  def lucidity(%Character{hit_points: {cur_hp, _}}) do
    cond do
      cur_hp <= 0 -> :unconscious
      cur_hp > 0 -> :conscious
    end

    # TODO: spells for confused/dazed?
  end

  def add_to_inventory(%Character{} = c, %Item{} = item) do
    if inventory_weight(c) + item.weight > c.inven_cap do
      {:error, :too_heavy}
    else
      inventory = Map.update(c.inventory, item.name, item, fn item -> %Item{item | quantity: item.quantity + 1} end)
      {:ok, %Character{c | inventory: inventory}}
    end
  end

  def dec_inventory_quantity(%Character{} = c, item) do
    case Map.fetch(c.inventory, item) do
      {:ok, %Item{quantity: 1}} ->
        %Character{c | inventory: Map.delete(c.inventory, item)}

      {:ok, %Item{quantity: quantity} = i} ->
        %Character{c | inventory: Map.put(c.inventory, item, %Item{i | quantity: quantity - 1})}
    end
  end

  def inventory_weight(%Character{} = c) do
    c.inventory
    |> Stream.map(fn {_, %Item{weight: weight, quantity: quantity}} -> weight * quantity end)
    |> Enum.sum()
  end

  def attack(c1, item, c2, advantage \\ 0)

  def attack(%Character{} = c1, %{type: %Weapon{}} = item, %Character{} = c2, advantage) do
    # TODO: status effects, saving rolls?

    hit_modifier =
      Enum.reduce(item.type.proficiency_types, 0, &(ability_modifier(c1, &1) + &2))

    hit_roll = GameEngine.roll(20)

    if hit_roll + hit_modifier + advantage >= armor_class(c2) do
      armor_damage_modifier =
        Enum.reduce(
          item.type.damage_types,
          0,
          &(c2.armor |> Map.get(:type) |> Armor.damage_modifiers() |> Map.get(&1, 0) |> Kernel.+(&2))
        )

      damage_roll = GameEngine.roll(item.type.damage_max)
      c2_ = subtract_hp(c2, damage_roll + armor_damage_modifier)

      {:ok, hit_roll, hit_modifier, armor_class(c2), damage_roll, armor_damage_modifier, c2_}
    else
      {:miss, hit_roll, hit_modifier, armor_class(c2)}
    end
  end

  def attack(%Character{} = _c1, item, %Character{} = c2, advantage) do
    hit_roll = GameEngine.roll(20)

    if hit_roll + advantage >= armor_class(c2) do
      damage_roll = GameEngine.roll(item.type.damage_max)
      c2_ = subtract_hp(c2, damage_roll)

      {:ok, hit_roll, 0, armor_class(c2), damage_roll, 0, c2_}
    else
      {:miss, hit_roll, 0, armor_class(c2)}
    end
  end

  defimpl String.Chars do
    def to_string(%Character{} = character), do: character.name
  end

  defimpl Inspect do
    defp map_ability_scores(character) do
      Enum.map_join(character.ability_scores, " / ", fn {name, value} ->
        "#{value} #{name |> Atom.to_string() |> String.slice(0..2)}"
      end)
    end

    def inspect(%Character{} = character, _opts) do
      {cur_hp, max_hp} = character.hit_points

      "#{character.name} @ #{cur_hp}/#{max_hp}HP (#{map_ability_scores(character)}) #{map_size(character.inventory)} item(s) in inventory, wearing #{character.armor.name}"
    end
  end
end
