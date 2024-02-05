defmodule RPG.GameEngine.GameArea.Arena.Lobby do
  @behaviour RPG.GameEngine.GameArea

  @impl RPG.GameEngine.GameArea
  def init_area() do
    {%{}, :roaming,
     "Welcome to the arena! Your party will fight fierce monsters until...well, until you all die! Travel to the next area to begin!"}
  end

  @impl RPG.GameEngine.GameArea
  def next_area(), do: {:ok, RPG.GameEngine.GameArea.Arena}

  @impl RPG.GameEngine.GameArea
  def prev_area() do
    # TODO: see comment in Arena
    :none
  end

  @impl RPG.GameEngine.GameArea
  def npc_action(_party, _npc_id), do: :none
end
