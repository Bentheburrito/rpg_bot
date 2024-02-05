defmodule RPG.Consumer do
  @moduledoc """
  The centralized Matrix event consumer/dispatcher
  """

  use GenServer

  require Logger
  alias Polyjuice.Client.Room

  @action_prefix "$"

  ### API

  @required_opts [:access_token, :homeserver, :storage, :user_id]
  def start_link(opts) do
    if Enum.all?(@required_opts, &Keyword.has_key?(opts, &1)) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    else
      {:stop,
       "Please include all of the following required opts when starting a consumer: #{Enum.join(@required_opts, ", ")}"}
    end
  end

  ### IMPL

  defguardp is_self(user_id, state) when state.user_id == user_id

  @impl GenServer
  def init(opts) do
    opts = Keyword.put(opts, :handler, self())

    opts
    |> Keyword.fetch!(:homeserver)
    |> Polyjuice.Client.start_link_and_get_client(opts)
    |> case do
      {:ok, _pid, client} ->
        {
          :ok,
          opts
          |> Map.new()
          |> Map.put(:client, client)
        }

      # TODO: PR :polyjuice_client to correct the start_link_and_get_client spec
      error ->
        error
    end
  end

  @impl GenServer
  def handle_info({:polyjuice_client, :message, {_, %{"sender" => sender}}}, state) when is_self(sender, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        {:polyjuice_client, :message, {room_id, %{"content" => %{"msgtype" => "m.text"} = message} = event}},
        state
      ) do
    # if String.starts_with?(message["body"], "hola") do
    #   Room.send_message(state.client, room_id, %{message | "msgtype" => "m.notice"})
    # end

    if String.starts_with?(message["body"], @action_prefix) do
      case RPG.handle_action(room_id, event["sender"], String.trim_leading(message["body"], @action_prefix)) do
        {:reply, response} -> send_message(state, room_id, response)
        :invalid_action -> send_message(state, room_id, invalid_action_message())
        :error -> send_message(state, room_id, "No party registered")
      end
    end

    {:noreply, state}
  end

  # TODO: just one handle_info, delegate to fns named after the event - e.g. def invite(room_id, inviter, invite_state)
  @impl GenServer
  def handle_info({:polyjuice_client, :invite, {room_id, _inviter, _invite_state}}, state) do
    Room.join(state.client, room_id)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:polyjuice_client, _event, _params}, state) do
    # IO.inspect(params, label: "Unhandled event: #{event}")
    {:noreply, state}
  end

  # RPG NPC events
  @impl GenServer
  def handle_info({:rpg, room_id, message}, state) do
    send_message(state, room_id, message)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_unknown_message, state) do
    # IO.inspect(unknown_message, label: "Unknown message")
    {:noreply, state}
  end

  def send_message(state, room_id, message) do
    {status, formatted, maybe_errs} = Earmark.as_html(message)

    unless status == :ok do
      Logger.warning(
        "Earmark.as_html returned #{status} with errors: #{inspect(maybe_errs)}. Sending formatted msg anyway: #{inspect(formatted)}"
      )
    end

    Room.send_message(state.client, room_id, %{
      "body" => message,
      "format" => "org.matrix.custom.html",
      "formatted_body" => formatted,
      "msgtype" => "m.text"
    })
  end

  defp invalid_action_message() do
    """
    I did not understand the action, please make sure it's of the form `#{@action_prefix}#{RPG.action_form()}`.

    TODO: Explain the different parts of the action form
    """
  end
end
