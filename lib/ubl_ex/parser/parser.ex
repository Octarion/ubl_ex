defmodule UblEx.Parser.Parser do
  @moduledoc """
  Generic XML parser that can be configured with different schemas and extractors.
  This module provides a namespace-agnostic way to parse XML documents.
  """

  import SweetXml

  @type xpath_spec :: %{
          required(:path) => charlist(),
          optional(:type) => :string | :float | :integer | :list,
          optional(:transform) => (any() -> any())
        }

  @type field_spec :: %{atom() => xpath_spec()}

  @type schema_config :: %{
          required(:document_type_selector) => charlist(),
          required(:document_types) => %{String.t() => field_spec()},
          optional(:namespaces) => %{atom() => String.t()},
          optional(:global_transforms) => %{atom() => (any() -> any())}
        }

  @doc """
  Parse XML document using the provided schema configuration.

  ## Parameters
  - `xml_content`: The XML content as a string
  - `schema_config`: Configuration defining how to parse the document
  - `target_type`: Optional specific document type to parse for

  ## Returns
  - `{:ok, {document_type, parsed_data}}` on success
  - `{:error, reason}` on failure

  ## Example Schema Config
  ```elixir
  %{
    document_type_selector: ~x"name(/*)"s,
    document_types: %{
      "Invoice" => %{
        date: %{path: ~x"//cbc:IssueDate/text()"s},
        amount: %{path: ~x"//cbc:PayableAmount/text()"f},
        number: %{path: ~x"./cbc:ID/text()"s, transform: &parse_invoice_id/1}
      },
      "CreditNote" => %{
        date: %{path: ~x"//cbc:IssueDate/text()"s},
        amount: %{path: ~x"//cbc:PayableAmount/text()"f}
      }
    },
    namespaces: %{cbc: "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"},
    global_transforms: %{
      amount: &Decimal.from_float/1
    }
  }
  ```
  """
  @spec parse(String.t(), schema_config(), String.t() | nil) ::
          {:ok, {String.t(), map()}} | {:error, String.t()}
  def parse(xml_content, schema_config, target_type \\ nil) do
    with {:ok, doc_type} <- get_document_type(xml_content, schema_config),
         {:ok, field_spec} <- get_field_spec(doc_type, schema_config, target_type) do
      if field_spec[:delegate_to_inner] do
        parse_sbdh_wrapped(xml_content, schema_config)
      else
        with {:ok, parsed_data} <- extract_fields(xml_content, field_spec, schema_config) do
          {:ok, {doc_type, parsed_data}}
        end
      end
    end
  end

  defp parse_sbdh_wrapped(xml_content, schema_config) do
    inner_doc_type =
      xml_content
      |> xpath(
        ~x"local-name(//*/*[local-name()='ApplicationResponse' or local-name()='Invoice' or local-name()='CreditNote'])"s
      )

    case inner_doc_type do
      inner when inner in ["Invoice", "CreditNote", "ApplicationResponse"] ->
        inner_xml = extract_inner_document(xml_content, inner)

        with {:ok, field_spec} <- get_field_spec(inner, schema_config, nil),
             {:ok, parsed_data} <- extract_fields(inner_xml, field_spec, schema_config) do
          {:ok, {inner, parsed_data}}
        end

      _ ->
        {:error, "Unknown inner document type in SBDH: #{inner_doc_type}"}
    end
  end

  defp extract_inner_document(xml_content, doc_type) do
    xml_content
    |> xpath(~x"//*[local-name()='#{doc_type}']"e)
    |> :xmerl.export_simple_element(:xmerl_xml)
    |> to_string()
  end

  @doc """
  Extract specific fields from XML using a field specification.
  """
  @spec extract_fields(String.t(), field_spec(), schema_config()) ::
          {:ok, map()} | {:error, String.t()}
  def extract_fields(xml_content, field_spec, schema_config) do
    parsed_data =
      field_spec
      |> Enum.reduce(%{}, fn {field_name, spec}, acc ->
        value = extract_field_value(xml_content, spec, schema_config)
        Map.put(acc, field_name, value)
      end)

    {:ok, parsed_data}
  rescue
    e -> {:error, "Failed to extract fields: #{inspect(e)}"}
  end

  @doc """
  Get the document type from XML content.
  """
  @spec get_document_type(String.t(), schema_config()) :: {:ok, String.t()} | {:error, String.t()}
  def get_document_type(xml_content, %{document_type_selector: selector}) do
    raw_result = xml_content |> xpath(selector)
    doc_type = convert_xpath_result(raw_result)

    if doc_type && doc_type != "",
      do: {:ok, doc_type},
      else: {:error, "Could not determine document type"}
  rescue
    e -> {:error, "Failed to get document type: #{inspect(e)}"}
  end

  @doc """
  Get available document types from schema.
  """
  @spec get_available_types(schema_config()) :: [String.t()]
  def get_available_types(%{document_types: types}) do
    Map.keys(types)
  end

  # Private functions

  defp get_field_spec(doc_type, %{document_types: types}, target_type) do
    cond do
      target_type && target_type != doc_type ->
        {:error, "Expected document type '#{target_type}' but got '#{doc_type}'"}

      Map.has_key?(types, doc_type) ->
        {:ok, types[doc_type]}

      true ->
        {:error, "Unsupported document type: #{doc_type}"}
    end
  end

  defp extract_field_value(_xml_content, %{transform: transform_fn} = spec, _schema_config)
       when not is_map_key(spec, :path) do
    transform_fn.(nil)
  end

  defp extract_field_value(xml_content, %{path: path} = spec, schema_config) do
    raw_value = xml_content |> xpath(path)
    converted_value = convert_xpath_result(raw_value)

    transformed_value =
      case Map.get(spec, :transform) do
        nil -> converted_value
        transform_fn -> transform_fn.(converted_value)
      end

    final_value =
      case get_in(schema_config, [:global_transforms, spec[:field_name]]) do
        nil -> transformed_value
        global_transform -> global_transform.(transformed_value)
      end

    final_value
  rescue
    _e ->
      nil
  end

  defp convert_xpath_result(result) when is_binary(result), do: result
  defp convert_xpath_result(result) when is_number(result), do: result
  defp convert_xpath_result(result) when is_list(result), do: result
  defp convert_xpath_result(result) when is_tuple(result), do: result

  defp convert_xpath_result(result) do
    to_string(result)
  rescue
    _ -> nil
  end
end
