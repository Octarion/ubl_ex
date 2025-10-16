defmodule UblEx.Parser.SaxyDOM do
  @moduledoc """
  Simple DOM builder using Saxy for better memory efficiency than xmerl.
  Provides XPath-like querying interface compatible with existing code.
  """

  defmodule Builder do
    @moduledoc false
    @behaviour Saxy.Handler

    defstruct stack: [], result: nil

    def new do
      %__MODULE__{stack: [], result: nil}
    end

    @impl Saxy.Handler
    def handle_event(:start_document, _prolog, state) do
      {:ok, state}
    end

    @impl Saxy.Handler
    def handle_event(:end_document, _data, state) do
      {:ok, state}
    end

    @impl Saxy.Handler
    def handle_event(:start_element, {name, attributes}, state) do
      element = {normalize_name(name), normalize_attributes(attributes), []}
      new_stack = [element | state.stack]
      {:ok, %{state | stack: new_stack}}
    end

    @impl Saxy.Handler
    def handle_event(:end_element, _name, %{stack: [element | rest]} = state) do
      {tag, attrs, children} = element
      reversed_children = Enum.reverse(children)
      completed_element = {tag, attrs, reversed_children}

      case rest do
        [] ->
          {:ok, %{state | stack: [], result: completed_element}}

        [{parent_tag, parent_attrs, parent_children} | rest_stack] ->
          updated_parent = {parent_tag, parent_attrs, [completed_element | parent_children]}
          {:ok, %{state | stack: [updated_parent | rest_stack]}}
      end
    end

    @impl Saxy.Handler
    def handle_event(:characters, _chars, %{stack: []} = state) do
      {:ok, state}
    end

    def handle_event(:characters, chars, %{stack: [{tag, attrs, children} | rest]} = state) do
      trimmed = String.trim(chars)

      new_children =
        if trimmed != "" do
          [trimmed | children]
        else
          children
        end

      updated_element = {tag, attrs, new_children}
      {:ok, %{state | stack: [updated_element | rest]}}
    end

    defp normalize_name(name) when is_binary(name) do
      case String.split(name, ":") do
        [_ns, local] -> local
        [local] -> local
      end
    end

    defp normalize_attributes(attributes) do
      Enum.map(attributes, fn {name, value} ->
        {normalize_name(name), value}
      end)
    end
  end

  @doc """
  Parse XML string into a DOM tree using Saxy.
  """
  def parse(xml_string) when is_binary(xml_string) do
    case Saxy.parse_string(xml_string, Builder, Builder.new(), []) do
      {:ok, %Builder{result: result}} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Query the DOM tree with XPath-like syntax.
  Supports a subset of XPath used in the current codebase.
  """
  def xpath(xml_string, path_spec) when is_binary(xml_string) do
    case parse(xml_string) do
      {:ok, dom} -> xpath(dom, path_spec)
      {:error, _} = error -> error
    end
  end

  def xpath(dom, path_spec) when is_tuple(dom) do
    query_dom(dom, path_spec)
  end

  defp query_dom(dom, path) when is_binary(path) do
    cond do
      String.ends_with?(path, "s") -> query_string(dom, String.slice(path, 0..-2//1))
      String.ends_with?(path, "f") -> query_float(dom, String.slice(path, 0..-2//1))
      String.ends_with?(path, "i") -> query_integer(dom, String.slice(path, 0..-2//1))
      String.ends_with?(path, "l") -> query_list(dom, String.slice(path, 0..-2//1))
      String.ends_with?(path, "sl") -> query_string_list(dom, String.slice(path, 0..-3//1))
      String.ends_with?(path, "e") -> query_element(dom, String.slice(path, 0..-2//1))
      true -> nil
    end
  end

  defp query_string(dom, path) do
    case find_text(dom, parse_path(path)) do
      nil -> ""
      text -> to_string(text)
    end
  end

  defp query_float(dom, path) do
    case query_string(dom, path <> "s") do
      "" ->
        nil

      str ->
        case Float.parse(str) do
          {float, _} -> float
          :error -> nil
        end
    end
  end

  defp query_integer(dom, path) do
    case query_string(dom, path <> "s") do
      "" ->
        nil

      str ->
        case Integer.parse(str) do
          {int, _} -> int
          :error -> nil
        end
    end
  end

  defp query_list(dom, path) do
    find_all_elements(dom, parse_path(path))
  end

  defp query_string_list(dom, path) do
    elements = find_all_elements(dom, parse_path(path))
    Enum.map(elements, &extract_text/1)
  end

  defp query_element(dom, path) do
    find_element(dom, parse_path(path))
  end

  defp parse_path(path) do
    path
    |> String.replace(~r/^~x"/, "")
    |> String.replace(~r/".*$/, "")
    |> String.replace("//", "")
    |> String.replace("./", "")
    |> String.split("/", trim: true)
    |> Enum.map(&parse_path_segment/1)
  end

  defp parse_path_segment(segment) do
    cond do
      String.starts_with?(segment, "@") ->
        {:attribute, String.trim_leading(segment, "@")}

      String.contains?(segment, "[") ->
        [name, predicate] = String.split(segment, "[", parts: 2)
        predicate = String.trim_trailing(predicate, "]")
        {:element_with_predicate, name, predicate}

      String.contains?(segment, "text()") ->
        {:text}

      segment == "*" ->
        {:wildcard}

      true ->
        {:element, segment}
    end
  end

  defp find_text(dom, path_segments) do
    case find_by_path(dom, path_segments) do
      {:text, text} -> text
      {_tag, _attrs, children} -> extract_text({:element, [], children})
      nil -> nil
    end
  end

  defp find_element(dom, path_segments) do
    find_by_path(dom, path_segments)
  end

  defp find_all_elements(dom, path_segments) do
    find_all_by_path(dom, path_segments)
  end

  defp find_by_path(dom, []), do: dom

  defp find_by_path({tag, attrs, children}, [{:element, name} | rest]) do
    case Enum.find(children, &match_element?(&1, name)) do
      nil -> search_descendants({tag, attrs, children}, [{:element, name} | rest])
      element -> find_by_path(element, rest)
    end
  end

  defp find_by_path({_tag, attrs, _children}, [{:attribute, attr_name}]) do
    case List.keyfind(attrs, attr_name, 0) do
      {^attr_name, value} -> value
      nil -> nil
    end
  end

  defp find_by_path({_tag, _attrs, children}, [{:text}]) do
    extract_text({:element, [], children})
  end

  defp find_by_path(dom, [{:wildcard} | rest]) do
    {_tag, _attrs, children} = dom

    Enum.find_value(children, fn child ->
      if is_tuple(child) do
        find_by_path(child, rest)
      else
        nil
      end
    end)
  end

  defp find_by_path(_dom, _path), do: nil

  defp search_descendants({_tag, _attrs, children}, path) do
    Enum.find_value(children, fn child ->
      if is_tuple(child) do
        find_by_path(child, path) || search_descendants(child, path)
      else
        nil
      end
    end)
  end

  defp find_all_by_path({_tag, _attrs, children}, [{:element, name} | []]) do
    Enum.filter(children, &match_element?(&1, name))
  end

  defp find_all_by_path({_tag, _attrs, children}, path) do
    Enum.flat_map(children, fn child ->
      if is_tuple(child) do
        case find_by_path(child, path) do
          nil -> find_all_by_path(child, path)
          result when is_list(result) -> result
          result -> [result]
        end
      else
        []
      end
    end)
  end

  defp match_element?({tag, _attrs, _children}, name), do: tag == name
  defp match_element?(_, _), do: false

  defp extract_text({_tag, _attrs, children}) when is_list(children) do
    children
    |> Enum.filter(&is_binary/1)
    |> Enum.join("")
    |> String.trim()
  end

  defp extract_text(text) when is_binary(text), do: String.trim(text)
  defp extract_text(_), do: ""

  @doc """
  Export element to XML string (for SBDH inner document extraction).
  """
  def export_element({tag, attrs, children}) do
    attrs_str =
      if attrs == [] do
        ""
      else
        " " <>
          Enum.map_join(attrs, " ", fn {k, v} ->
            ~s(#{k}="#{escape_xml(v)}")
          end)
      end

    children_str = export_children(children)

    "<#{tag}#{attrs_str}>#{children_str}</#{tag}>"
  end

  defp export_children(children) do
    Enum.map_join(children, "", fn
      {_tag, _attrs, _children} = element -> export_element(element)
      text when is_binary(text) -> escape_xml(text)
    end)
  end

  defp escape_xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
