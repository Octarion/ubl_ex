defmodule UblEx.Parser.SweetXmlCompat do
  @moduledoc """
  SweetXML compatibility layer using Saxy for better performance.

  This module provides the same API as SweetXml but uses Saxy underneath
  for faster parsing and better memory efficiency.
  """

  alias UblEx.Parser.SaxyDOM

  @doc """
  XPath query function compatible with SweetXml.xpath/2.
  """
  defmacro sigil_x(path, modifiers) do
    quote do
      path_with_modifiers(unquote(path), unquote(modifiers))
    end
  end

  def path_with_modifiers(path, modifiers) when is_list(modifiers) do
    modifier_str = to_string(modifiers)
    path <> modifier_str
  end

  @doc """
  Execute XPath query on XML content or DOM node.
  Compatible with SweetXml.xpath/2 and SweetXml.xpath/3.
  """
  def xpath(xml_or_dom, path_spec, subspec \\ nil)

  def xpath(xml_string, path, nil) when is_binary(xml_string) and is_binary(path) do
    SaxyDOM.xpath(xml_string, path)
  end

  def xpath(dom, path, nil) when is_tuple(dom) and is_binary(path) do
    SaxyDOM.xpath(dom, path)
  end

  def xpath(xml_string, base_path, path_specs)
      when is_binary(xml_string) and is_list(path_specs) do
    case SaxyDOM.parse(xml_string) do
      {:ok, dom} ->
        base_element = SaxyDOM.xpath(dom, base_path)

        if base_element do
          xpath(base_element, nil, path_specs)
        else
          %{}
        end

      {:error, _} ->
        %{}
    end
  end

  def xpath(dom, _base_path, path_specs) when is_tuple(dom) and is_list(path_specs) do
    Enum.reduce(path_specs, %{}, fn {key, path}, acc ->
      value = SaxyDOM.xpath(dom, path)
      Map.put(acc, key, value)
    end)
  end

  def xpath(xml_string, path_specs, nil) when is_binary(xml_string) and is_list(path_specs) do
    case SaxyDOM.parse(xml_string) do
      {:ok, dom} ->
        Enum.reduce(path_specs, %{}, fn {key, path}, acc ->
          value = SaxyDOM.xpath(dom, path)
          Map.put(acc, key, value)
        end)

      {:error, _} ->
        %{}
    end
  end

  @doc """
  Export element to XML string.
  Compatible with :xmerl.export_simple_element/2.
  """
  def export_simple_element(element) do
    SaxyDOM.export_element(element)
  end

  defmacro __using__(_opts) do
    quote do
      import UblEx.Parser.SweetXmlCompat,
        only: [sigil_x: 2, xpath: 2, xpath: 3, path_with_modifiers: 2]

      alias UblEx.Parser.SweetXmlCompat
    end
  end
end
