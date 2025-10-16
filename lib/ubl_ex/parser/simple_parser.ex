defmodule UblEx.Parser.SimpleParser do
  @moduledoc """
  Simple direct parser using Saxy to parse UBL XML into maps.
  No XPath, no intermediate DOM - just straightforward event handling.
  """

  alias UblEx.Parser.UblHandler

  @doc """
  Parse UBL XML content directly into a map.
  Supports Invoice, CreditNote, ApplicationResponse, and SBDH-wrapped documents.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(xml_content) when is_binary(xml_content) do
    case Saxy.parse_string(xml_content, UblHandler, UblHandler.new(), []) do
      {:ok, %UblHandler{result: result}} when map_size(result) > 0 ->
        {:ok, result}

      {:ok, _} ->
        {:error, "Could not parse UBL document - unknown format"}

      {:error, %Saxy.ParseError{} = error} ->
        {:error, "XML parse error: #{Exception.message(error)}"}

      {:error, reason} ->
        {:error, "Parse error: #{inspect(reason)}"}
    end
  end
end
