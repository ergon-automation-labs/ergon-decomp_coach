defmodule BotArmyDecompCoach.Services.DecomposeService do
  @moduledoc """
  Handles decomposition requests: takes a vague project description,
  asks clarifying questions via LLM, and creates a structured GTD task.
  """

  require Logger
  alias BotArmyCore.NATS

  def handle_request(request) do
    Logger.info("[DecomposeService] Processing: #{request.request_id}")

    with {:ok, context} <- load_user_context(),
         {:ok, questions} <- generate_clarifying_questions(request, context),
         {:ok, task} <- create_gtd_task(request, questions) do
      {:ok, %{task_id: task.id, questions: questions, request_id: request.request_id}}
    else
      {:error, reason} ->
        Logger.error("[DecomposeService] Failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_user_context do
    # Fetch current GTD state, companion reflection history, energy state
    # This would call bridge.task.list, bridge.chat, etc.
    {:ok, %{gtd_active_count: 0, recent_blocks: []}}
  end

  defp generate_clarifying_questions(request, _context) do
    prompt = """
    The user said: "#{request.user_message}"

    Ask 3-4 clarifying questions to help them break down this vague project.
    Focus on:
    1. What's blocking them right now?
    2. What's the first tiny step?
    3. How much time could they realistically spend?

    Keep questions conversational, not robotic.
    """

    case call_llm(prompt) do
      {:ok, response} ->
        questions = parse_questions(response)
        {:ok, questions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_gtd_task(request, questions) do
    task_body = """
    #{request.user_message}

    ## Context
    Questions asked during decomposition:
    #{format_questions(questions)}

    ## Verification
    Test case: User responds to clarifying questions
    Test command: nats request --server nats://localhost:4223 bridge.task.list '{}' --timeout 3s
    """

    case call_bridge_create_task(task_body) do
      {:ok, task} -> {:ok, task}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_llm(prompt) do
    case NATS.request("llm.complete", Jason.encode!(%{"prompt" => prompt}), timeout: 30_000) do
      {:ok, response} ->
        case Jason.decode(response.body) do
          {:ok, %{"result" => text}} -> {:ok, text}
          {:ok, %{"completion" => text}} -> {:ok, text}
          {:ok, data} -> {:ok, inspect(data)}
          {:error, reason} -> {:error, "Failed to decode LLM response: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "LLM request failed: #{inspect(reason)}"}
    end
  end

  defp call_bridge_create_task(body) do
    request = %{
      "title" => "New decomposition task",
      "description" => body,
      "status" => "todo"
    }

    case NATS.request("bridge.task.create", Jason.encode!(request), timeout: 15_000) do
      {:ok, response} ->
        case Jason.decode(response.body) do
          {:ok, %{"task_id" => id}} -> {:ok, %{id: id, title: "New decomposition task"}}
          {:ok, %{"id" => id}} -> {:ok, %{id: id, title: "New decomposition task"}}
          {:ok, data} -> {:ok, %{id: "created", title: inspect(data)}}
          {:error, reason} -> {:error, "Failed to decode task response: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Task creation failed: #{inspect(reason)}"}
    end
  end

  defp parse_questions(response) do
    response
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^\d+\./))
  end

  defp format_questions(questions) do
    Enum.map_join(questions, "\n", &"- #{&1}")
  end
end
