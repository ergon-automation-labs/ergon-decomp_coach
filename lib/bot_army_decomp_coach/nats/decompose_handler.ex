defmodule BotArmyDecompCoach.NATS.DecomposeHandler do
  @moduledoc """
  NATS responder for coach.decompose

  Receives: {"user_message": "I have a vague project..."}
  Responds: {"task_id": "...", "questions": [...], "request_id": "..."}
  """

  require Logger
  alias BotArmyDecompCoach.Services.DecomposeService
  alias BotArmyDecompCoach.Schemas.DecomposeRequest

  def handle(msg) do
    with {:ok, body} <- Jason.decode(msg),
         {:ok, request} <- parse_request(body),
         {:ok, response} <- DecomposeService.handle_request(request) do
      Jason.encode!(response)
    else
      {:error, reason} ->
        Logger.error("[DecomposeHandler] Error: #{inspect(reason)}")
        Jason.encode!(%{"error" => inspect(reason)})
    end
  end

  defp parse_request(body) when is_map(body) do
    user_message = Map.get(body, "user_message") || Map.get(body, "message")

    if is_nil(user_message) or user_message == "" do
      {:error, "Missing or empty user_message"}
    else
      request = DecomposeRequest.new(user_message, request_id: Map.get(body, "request_id"))
      {:ok, request}
    end
  end

  defp parse_request(_), do: {:error, "Invalid request format"}
end
