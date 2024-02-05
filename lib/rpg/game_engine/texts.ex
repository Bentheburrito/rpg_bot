defmodule RPG.GameEngine.Texts do
  @moduledoc """
  Helper functions for creating text from data.
  """

  def modifier(0, _label), do: ""
  def modifier(value, "") when value > 0, do: modifier("+", value, "")
  def modifier(value, "") when value < 0, do: modifier("", value, "")
  def modifier(value, label) when value > 0, do: modifier("+", value, " " <> label)
  def modifier(value, label) when value < 0, do: modifier("", value, " " <> label)

  defp modifier(value_prefix, value, label), do: "(#{value_prefix}#{value}#{label})"
end
