defmodule Quickbase.Error do
  @moduledoc """
  Raised/returned when the Quickbase API responds with a non-200 status.

  Carries the HTTP `status` and decoded response `body` (Quickbase error
  bodies are maps with `"message"` and `"description"` keys).
  """

  defexception [:status, :body]

  @type t :: %__MODULE__{status: non_neg_integer(), body: term()}

  @impl true
  def message(%__MODULE__{status: status, body: body}) do
    detail =
      case body do
        %{"message" => msg} when is_binary(msg) -> ": #{msg}"
        _ -> ""
      end

    "Quickbase API returned status #{status}#{detail}"
  end
end
