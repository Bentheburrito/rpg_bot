defmodule RPG.GameEngine.Item.Consumable do
  @moduledoc """
  An item that can be consumed by a Character.
  """

  @type effect :: :nothing | {:health, integer()}

  @type t() :: %__MODULE__{
          effect: effect()
        }
  defstruct effect: :nothing
end
