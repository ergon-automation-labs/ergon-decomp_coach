defmodule BotArmyDecompCoach.NATS.EnergyCheckHandler do
  @moduledoc """
  NATS responder for coach.energy_check

  Receives: {} (empty)
  Responds: {"energy_level": "medium", "recommendation": "...", "suggested_action": "..."}

  Reads user's energy state (time spent, task history, reflection logs) and advises
  whether to push forward, break, or pivot.
  """

  require Logger

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

  defp assess_energy() do
    # Gather signals:
    # 1. How long have you been focused on current task?
    # 2. Historical patterns (companion reflection)
    # 3. Tasks completed today
    # 4. Breaks taken
    # TODO: wire to companion history + bridge

    {:ok,
     %{
       "time_on_current" => 90,
       # minutes
       "today_completed" => 3,
       # tasks
       "breaks_taken" => 1,
       "hyperfocus_threshold" => 120,
       # minutes user typically burns out
       "energy_pattern" => "declining"
     }}
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
