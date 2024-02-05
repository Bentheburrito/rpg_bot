defmodule RPG.GameEngine.GameArea do
  alias RPG.Party
  alias RPG.GameEngine.Character

  @type area_traversal_result :: {:ok, module()} | :none
  @type npc_id :: any()

  @callback next_area() :: area_traversal_result()
  @callback prev_area() :: area_traversal_result()
  @callback init_area() :: {npcs :: %{npc_id => Character.t()}, next_state :: Party.states(), exposition :: String.t()}

  @callback npc_action(Party.t(), npc_id) :: {:ok, String.t()} | :none
end
