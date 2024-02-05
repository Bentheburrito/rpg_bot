defmodule RPG.GameEngine.Item.Common do
  alias RPG.GameEngine
  alias RPG.GameEngine.Item.Consumable
  alias RPG.GameEngine.Item
  alias RPG.GameEngine.Item.Armor
  alias RPG.GameEngine.Item.Weapon

  ### ARMOR

  def light_leather_armor do
    %Item{
      type: %Armor{
        speed_mod: 0,
        magic_cost_mod: 0,
        armor_class: 10,
        damage_modifiers: %{}
      },
      name: "Light Leather Armor",
      description: "A thick, yet light garment providing some protection for the upper torso.",
      throwable?: true,
      weight: 8
    }
  end

  def heavy_chainmail_armor do
    %Item{
      type: %Armor{
        speed_mod: -2,
        magic_cost_mod: 0,
        armor_class: 15,
        damage_modifiers: %{slash: -2, frost: 2}
      },
      name: "Heavy Chainmail Armor",
      description: "An easy choice for any knight.",
      throwable?: false,
      weight: 20
    }
  end

  ### SWORDS

  def bronze_short_sword do
    %Item{
      type: %Weapon{
        attack_type: :melee,
        damage_types: [:slash],
        damage_max: 6,
        wield_type: :one_hand,
        proficiency_types: [:strength, :dexterity]
      },
      name: "Bronze Short Sword",
      description: "A short sword made of old bronze. A favorite of many goblin in the west",
      throwable?: true,
      weight: 3
    }
  end

  def iron_long_sword do
    %Item{
      type: %Weapon{
        attack_type: :melee,
        damage_types: [:slash],
        damage_max: 8,
        wield_type: :one_hand,
        proficiency_types: [:strength]
      },
      name: "Iron Long Sword",
      description: "A fine blade smithed in the forges of the East Mountains",
      throwable?: true,
      weight: 6
    }
  end

  ### POTIONS

  def minor_healing_potion do
    %Item{
      type: %Consumable{
        effect: {:health, GameEngine.roll(6)}
      },
      name: "Potion of Minor Healing",
      description: "A blend of herbs with magical healing properties",
      throwable?: true,
      weight: 2
    }
  end
end
