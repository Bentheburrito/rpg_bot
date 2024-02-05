defmodule RPG.GameEngine.Item.Armor do
  @moduledoc """
  An item that can be worn by a Character to provide it specific benefits.

  Benefits may take the form of:
  - protection (with possibly increased protection against certain types of damage)
  - modifiers, including temperature (e.g. keeps Character warm in a snowstorm), ability scores, (de)buffs to movement
    speed or magical abilities.
  """
  alias RPG.GameEngine.Item.Armor

  @type t() :: %__MODULE__{
          speed_mod: integer(),
          magic_cost_mod: integer(),
          armor_class: integer(),
          damage_modifiers: %{Weapon.damage_type() => integer()}
        }
  defstruct speed_mod: 0, magic_cost_mod: 0, armor_class: 10, damage_modifiers: %{}

  def damage_modifiers(%Armor{damage_modifiers: dms}), do: dms
  def damage_modifiers(nil), do: %{}
end
