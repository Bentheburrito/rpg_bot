defmodule RPG.GameEngine.Item do
  @moduledoc """
  An item is some thing that exists in the game world. It can be observed, looted, stored in a Character's inventory,
  and used by Characters.
  """
  alias RPG.GameEngine.Item

  @type t() :: %__MODULE__{
          type: :normal | Item.Armor.t() | Item.Weapon.t() | Item.Consumable.t(),
          name: String.t(),
          description: String.t(),
          throwable?: boolean(),
          weight: non_neg_integer(),
          quantity: non_neg_integer()
        }
  @enforce_keys [:name, :description, :weight]
  defstruct type: :normal, throwable?: true, name: nil, description: nil, weight: nil, quantity: 1

  defimpl String.Chars do
    def to_string(%Item{name: name}), do: name
  end

  defimpl Inspect do
    alias RPG.GameEngine.Texts

    def inspect(%Item{} = item, _opts) do
      """
      **#{item.name} x#{item.quantity}**\s\s
      Type: #{type(item.type)}\s\s
      Weight: #{item.weight}kg/each\s\s
      #{if item.throwable?, do: "Can", else: "Can't"} be thrown.\s\s
      """
    end

    defp type(:normal), do: "ordinary"
    defp type(%Item.Armor{}), do: "Armor"
    defp type(%Item.Weapon{}), do: "Weapon"
    defp type(%Item.Consumable{effect: :nothing}), do: "Consumable"
    defp type(%Item.Consumable{effect: {:health, hp}}), do: "Consumable #{Texts.modifier(hp, "HP")}"
  end
end
