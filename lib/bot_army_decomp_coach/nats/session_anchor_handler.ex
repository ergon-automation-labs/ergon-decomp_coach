defmodule BotArmyDecompCoach.NATS.SessionAnchorHandler do
  @moduledoc """
  NATS responder for coach.session_anchor

  Receives: {} (empty)
  Responds: {"current_task": {...}, "context_window": "...", "recommendation": "..."}

  Helps user reconnect to their work after context switch.
  """

  require Logger
  alias BotArmyLibraryCore.NATS

  def handle(_msg) do
    with {:ok, current_task} <- fetch_current_task(),
         {:ok, context} <- build_context_window(current_task) do
      response = %{
        current_task: current_task,
        context_window: context,
        recommendation: generate_recommendation(current_task, context)
      }

      Jason.encode!(response)
    else
      {:error, reason} ->
        Logger.error("[SessionAnchorHandler] Error: #{inspect(reason)}")
        Jason.encode!(%{"error" => inspect(reason)})
    end
  end

  defp fetch_current_task do
    # Call bridge.task.list to find the active task
    case NATS.request("bridge.task.list", Jason.encode!(%{}), timeout: 15_000) do
      {:ok, response} ->
        case Jason.decode(response.body) do
          {:ok, %{"tasks" => [%{"id" => id, "title" => title} | _]}} ->
            {:ok, %{id: id, title: title, status: "in_progress"}}

          {:ok, %{"tasks" => []}} ->
            {:error, "No active tasks found"}

          {:error, reason} ->
            {:error, "Failed to decode task list: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Task list request failed: #{inspect(reason)}"}
    end
  end

  defp build_context_window(current_task) do
    # Pull context from bridge.chat (companion reflection/context)
    case NATS.request(
           "bridge.chat",
           Jason.encode!(%{"query" => "What was I working on before? What's the current blocker?"}),
           timeout: 15_000
         ) do
      {:ok, response} ->
        case Jason.decode(response.body) do
          {:ok, %{"response" => context}} ->
            {:ok, %{"last_comment" => context, "task_id" => current_task.id}}

          {:ok, data} ->
            {:ok, %{"last_comment" => inspect(data), "task_id" => current_task.id}}

          {:error, reason} ->
            {:error, "Failed to decode context: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Context request failed: #{inspect(reason)}"}
    end
  end

  defp generate_recommendation(task, context) do
    "You were working on: #{task.title}. Last blocker: #{context["last_comment"]}. Ready to dive back in? (#{context["time_spent"]} so far)"
  end
end
