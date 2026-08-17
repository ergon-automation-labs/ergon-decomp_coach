defmodule BotArmyDecompCoach.NATS.Consumer do
  @moduledoc """
  NATS message consumer for decomp_coach.

  Subscribes to NATS subjects and routes messages to handlers.
  Uses standardized Reply format for request/reply patterns.

  All request/reply handlers should return responses using Reply helpers:
  - BotArmyRuntime.NATS.Reply.ok(data) for success
  - BotArmyRuntime.NATS.Reply.error(message, code) for errors
  """

  use GenServer
  require Logger

  @reconnect_delay_ms 5000
  @version Mix.Project.config()[:version]

  # Register subjects with their metadata for runtime discovery
  @subjects [
    %{
      subject: "coach.decompose",
      type: :request_reply,
      description: "Decompose vague project into tasks"
    },
    %{
      subject: "coach.session_anchor",
      type: :request_reply,
      description: "Get current task context after switch"
    },
    %{
      subject: "coach.energy_check",
      type: :request_reply,
      description: "Check energy level and get recommendation"
    }
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("Starting NATS consumer")

    state = %{
      subscriptions: [],
      conn: nil,
      opts: opts
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5000) do
      {:ok, conn} ->
        BotArmyRuntime.NATS.Connection.subscribe_to_status()
        Logger.info("Connected to NATS, subscribing to topics")

        subscriptions = subscribe_to_subjects(conn, @subjects)

        # Register subjects for runtime discovery
        BotArmyRuntime.Registry.register("decomp_coach", @subjects, @version)

        {:noreply, %{state | subscriptions: subscriptions, conn: conn}}

      {:error, _reason} ->
        Logger.warning("NATS connection not ready, will retry")
        Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:connect_retry, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers), fn ->
      Logger.debug("Received NATS message on subject: #{msg.topic}")
      process_message_type(msg, state)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("Disconnected from NATS, will reconnect")
    Process.send_after(self(), :connect_retry, @reconnect_delay_ms)
    {:noreply, %{state | subscriptions: [], conn: nil}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("Reconnected to NATS, re-subscribing")
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(:reconnect, state) do
    {:noreply, state, {:continue, :connect}}
  end

  # Subscribe to all subjects in @subjects list
  defp subscribe_to_subjects(conn, subjects) do
    subjects
    |> Enum.map(fn %{subject: subject} ->
      case Gnat.sub(conn, self(), subject) do
        {:ok, sub} ->
          Logger.info("Subscribed to #{subject}")
          sub

        {:error, reason} ->
          Logger.error("Failed to subscribe to #{subject}: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.filter(&(not is_nil(&1)))
  end

  # Dispatch message based on type (request/reply or pub/sub)
  defp process_message_type(msg, state) do
    if msg.reply_to do
      process_request_reply(msg, state)
    else
      process_pubsub(msg)
    end
  end

  defp process_request_reply(msg, state) do
    case msg.topic do
      "coach.decompose" ->
        handle_request_reply(msg, state, &BotArmyDecompCoach.NATS.DecomposeHandler.handle/1)

      "coach.session_anchor" ->
        handle_request_reply(msg, state, &BotArmyDecompCoach.NATS.SessionAnchorHandler.handle/1)

      "coach.energy_check" ->
        handle_request_reply(msg, state, &BotArmyDecompCoach.NATS.EnergyCheckHandler.handle/1)

      _ ->
        Logger.debug("Unknown request/reply subject: #{msg.topic}")
    end
  end

  defp process_pubsub(msg) do
    case BotArmyCore.NATS.Decoder.decode(msg.body) do
      {:ok, decoded_message} ->
        route_message(decoded_message, msg.topic)

      {:error, reason} ->
        Logger.warning("Failed to decode message from #{msg.topic}: #{inspect(reason)}")
    end
  end

  # Handle request/reply messages
  defp handle_request_reply(msg, state, handler_fn) do
    try do
      response = handler_fn.(msg.body)
      BotArmyCore.NATS.Connection.pub(state.conn, msg.reply_to, response)
      Logger.info("Responded to #{msg.topic}")
    rescue
      e ->
        Logger.error("Error handling #{msg.topic}: #{inspect(e)}")
        error_response = Jason.encode!(%{"error" => inspect(e)})
        BotArmyCore.NATS.Connection.pub(state.conn, msg.reply_to, error_response)
    end
  end

  # Message routing
  defp route_message(message, topic) do
    # Route decoded messages to appropriate handlers
    Logger.debug("Routing message from #{topic}")
  end

  # Request/reply handlers
  # defp handle_task_list(msg, state) do
  #   response =
  #     case get_tasks() do
  #       {:ok, tasks} ->
  #         BotArmyRuntime.NATS.Reply.ok(%{"tasks" => tasks})
  #
  #       {:error, reason} ->
  #         BotArmyRuntime.NATS.Reply.error(inspect(reason), :list_failed)
  #     end
  #
  #   if state.conn do
  #     Gnat.pub(state.conn, msg.reply_to, response)
  #   end
  # end
end
