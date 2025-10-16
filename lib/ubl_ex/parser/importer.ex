defmodule UblEx.Parser.Importer do
  @moduledoc """
  XML parsing and validation for UBL documents.
  """

  alias UblEx.Parser.{Parser, SchemaRegistry}

  @doc """
  Extract party information (supplier, customer, etc.) from XML.
  """
  @spec extract_party_info(String.t(), atom(), atom()) :: {:ok, map()} | {:error, String.t()}
  def extract_party_info(xml_content, schema_id, party_type) do
    with {:ok, schema} <- SchemaRegistry.get_schema(schema_id),
         {:ok, party_config} <- get_party_config(schema, party_type) do
      extract_party_data(xml_content, party_config)
    end
  end

  @doc """
  Validate XML against schema without importing.
  """
  @spec validate(String.t(), atom()) :: {:ok, {String.t(), map()}} | {:error, String.t()}
  def validate(xml_content, schema_id) do
    with {:ok, schema} <- SchemaRegistry.get_schema(schema_id) do
      Parser.parse(xml_content, schema)
    end
  end

  @doc """
  Get supported document types for a schema.
  """
  @spec get_supported_types(atom()) :: {:ok, [String.t()]} | {:error, String.t()}
  def get_supported_types(schema_id) do
    with {:ok, schema} <- SchemaRegistry.get_schema(schema_id) do
      {:ok, Parser.get_available_types(schema)}
    end
  end

  defp get_party_config(schema, party_type) do
    case get_in(schema, [:party_extraction, party_type]) do
      nil -> {:error, "Party type #{party_type} not configured in schema"}
      config -> {:ok, config}
    end
  end

  defp extract_party_data(xml_content, %{base_path: base_path, fields: fields}) do
    use UblEx.Parser.SweetXmlCompat

    try do
      party_data =
        xml_content
        |> xpath(
          base_path,
          fields
          |> Enum.map(fn {key, %{path: path}} -> {key, path} end)
          |> Enum.into([])
        )

      {:ok, party_data}
    rescue
      e -> {:error, "Failed to extract party data: #{inspect(e)}"}
    end
  end
end
