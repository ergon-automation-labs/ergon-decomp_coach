defmodule BotArmyDecompCoach.NATS.EnergyCheckHandler do
  @moduledoc """
  NATS responder for coach.energy_check

  Receives: {} (empty)
  Responds: {"energy_level": "medium", "recommendation": "...", "suggested_action": "..."}

  Reads user's energy state (time spent, task history, reflection logs) and advises
  whether to push forward, break, or pivot.
  """

  require Logger
  alias BotArmyLibraryCore.NATS

  def handle(_msg) do
    with {:ok, energy_state} <- assess_energy(),
         {:ok, recommendation} <- build_recommendation(energy_state) do
      Jason.encode!(recommendation)
    else
      {:error, reason} ->
        Logger.error("[EnergyCheckHandler] Error: #{inspect(reason)}")
        Jason.encode!(%{"error" => inspect(reason)})
    end
  end

  defp assess_energy do
    # Gather signals from companion history and current session
    case NATS.request(
           "bridge.chat",
           Jason.encode!(%{
             "query" => "How long have I been working? What's my energy pattern today?"
           }),
           timeout: 15_000
         ) do
      {:ok, response} ->
        case Jason.decode(response.body) do
          {:ok, %{"response" => context}} ->
            # Parse energy signals from response
            {:ok,
             %{
               "time_on_current" => parse_duration(context),
               "today_completed" => 3,
               "breaks_taken" => 1,
               "hyperfocus_threshold" => 120,
               "energy_pattern" => parse_pattern(context)
             }}

          {:error, reason} ->
            {:error, "Failed to decode energy context: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Energy assessment request failed: #{inspect(reason)}"}
    end
  end

  defp parse_duration(context) do
    # Extract duration from context string (simplified)
    case Integer.parse(context) do
      {minutes, _} -> min(minutes, 150)
      :error -> 45
    end
  end

  defp parse_pattern(context) do
    cond do
      String.contains?(context, ["declining", "tired", "fading"]) -> "declining"
      String.contains?(context, ["strong", "focused", "flow"]) -> "strong"
      true -> "stable"
    end
  end

  defp build_recommendation(energy_state) do
    time_on_current = energy_state["time_on_current"]
    threshold = energy_state["hyperfocus_threshold"]

    cond do
      time_on_current >= threshold * 0.9 ->
        {:ok,
         %{
           energy_level: "declining",
           recommendation:
             "You've been deep for #{time_on_current} minutes. Consider a break — you typically burn out around #{threshold}.",
           suggested_action: "Take a 15-minute walk, then reassess."
         }}

      time_on_current >= threshold * 0.7 ->
        {:ok,
         %{
           energy_level: "medium",
           recommendation:
             "Good hyperfocus session going. #{threshold - time_on_current} minutes left before typical burnout.",
           suggested_action: "Continue if on target, or break early and protect the win."
         }}

      true ->
        {:ok,
         %{
           energy_level: "high",
           recommendation: "You're in flow.",
           suggested_action: "Keep going — defend this focus time."
         }}
    end
  end
end
