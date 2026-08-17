defmodule BotArmyDecompCoach.NATS.SessionAnchorHandler do
  @moduledoc """
  NATS responder for coach.session_anchor

  Receives: {} (empty)
  Responds: {"current_task": {...}, "context_window": "...", "recommendation": "..."}

  Helps user reconnect to their work after context switch.
  """

  require Logger

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

  defp fetch_current_task() do
    # Call bridge.task.list to find the active task
    # TODO: wire to bridge
    {:ok, %{id: "task-123", title: "Decompose outreach automation", status: "in_progress"}}
  end

  defp build_context_window(current_task) do
    # Pull context from companion reflection, task history, etc.
    # TODO: call bridge.chat or companion history
    {:ok,
     %{
       "last_comment" => "Stuck on figuring out what 'automate' means",
       "time_spent" => "45 minutes",
       "verification_block" => "Test command: mix test --only handlers"
     }}
  end

  defp generate_recommendation(task, context) do
    "You were working on: #{task.title}. Last blocker: #{context["last_comment"]}. Ready to dive back in? (#{context["time_spent"]} so far)"
  end
end
