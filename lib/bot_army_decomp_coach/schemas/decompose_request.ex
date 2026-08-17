defmodule BotArmyDecompCoach.Schemas.DecomposeRequest do
  @moduledoc """
  Schema for decomposition coach requests.

  Handles requests like:
  "I have a vague project about automating my outreach"

  Coach asks clarifying questions, understands the work, creates a GTD task.
  """

  defstruct [
    :request_id,
    :user_message,
    :context,
    :conversation_history
  ]

  def new(user_message, opts \\ []) do
    %__MODULE__{
      request_id: opts[:request_id] || UUID.uuid4(),
      user_message: user_message,
      context: opts[:context] || %{},
      conversation_history: opts[:history] || []
    }
  end
end
