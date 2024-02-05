defmodule RPG.GameEngine.Item.Weapon do
  @moduledoc """
  An item that can be used by a Character to affect its environment, particularly by damaging other Characters.
  """

  @type attack_type :: :melee | :ranged
  @type damage_type :: :pierce | :blunt | :slash | :frost | :fire | :spirit | :smite | :poison
  @type wield_type :: :one_hand | :two_hands

  @type t() :: %__MODULE__{
          attack_type: attack_type(),
          damage_types: [damage_type()],
          damage_max: integer(),
          wield_type: wield_type(),
          proficiency_types: [Character.ability()]
        }
  defstruct attack_type: :melee, damage_types: [], damage_max: 6, wield_type: :one_hand, proficiency_types: []
end
