defmodule QuickbaseTest do
  use ExUnit.Case, async: true

  doctest Quickbase

  defp client(opts \\ []) do
    Quickbase.new(
      [realm: "demo.quickbase.com", token: "secret", plug: {Req.Test, __MODULE__}] ++ opts
    )
  end

  test "new/1 sets realm and token headers" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert Plug.Conn.get_req_header(conn, "qb-realm-hostname") == ["demo.quickbase.com"]
      assert Plug.Conn.get_req_header(conn, "authorization") == ["QB-USER-TOKEN secret"]
      Req.Test.json(conn, %{})
    end)

    assert {:ok, %{}} = Quickbase.list_fields(client(), "tbl")
  end

  test "query_records/2 posts the query body and returns the response" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/records/query"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(raw) == %{
               "from" => "tbl",
               "select" => [3, 6],
               "where" => "{'6'.EX.'Done'}",
               "sortBy" => [],
               "groupBy" => []
             }

      Req.Test.json(conn, %{"data" => [%{"6" => %{"value" => "Done"}}]})
    end)

    assert {:ok, %{"data" => [row]}} =
             Quickbase.query_records(client(),
               from: "tbl",
               select: [3, 6],
               where: "{'6'.EX.'Done'}"
             )

    assert Quickbase.value(row, 6) == "Done"
  end

  test "query_records/2 includes options only when skip/top given" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(raw)["options"] == %{"skip" => 10, "top" => 5}
      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:ok, _} = Quickbase.query_records(client(), from: "tbl", skip: 10, top: 5)
  end

  test "non-200 returns Quickbase.Error and bang raises it" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "Unauthorized"})
    end)

    assert {:error, %Quickbase.Error{status: 401} = error} =
             Quickbase.query_records(client(), from: "tbl")

    assert Exception.message(error) =~ "401"
    assert Exception.message(error) =~ "Unauthorized"

    assert_raise Quickbase.Error, fn -> Quickbase.query_records!(client(), from: "tbl") end
  end

  test "run_report/3 posts to the report endpoint with tableId" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.request_path == "/v1/reports/7/run"
      assert conn.query_string == "tableId=tbl"
      Req.Test.json(conn, %{"data" => []})
    end)

    assert {:ok, %{"data" => []}} = Quickbase.run_report(client(), 7, "tbl")
  end

  test "upsert_records/4 builds the records body with optional keys" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/records"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(raw) == %{
               "to" => "tbl",
               "data" => [%{"6" => %{"value" => "Task"}}],
               "mergeFieldId" => 3,
               "fieldsToReturn" => [3, 6]
             }

      Req.Test.json(conn, %{"metadata" => %{"createdRecordIds" => [1]}})
    end)

    assert {:ok, _} =
             Quickbase.upsert_records(client(), "tbl", [%{"6" => %{"value" => "Task"}}],
               merge_field_id: 3,
               fields_to_return: [3, 6]
             )
  end

  test "delete_records/3 sends DELETE with from/where body" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "DELETE"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(raw) == %{"from" => "tbl", "where" => "{'3'.EX.'1'}"}
      Req.Test.json(conn, %{"numberDeleted" => 1})
    end)

    assert {:ok, %{"numberDeleted" => 1}} =
             Quickbase.delete_records(client(), "tbl", "{'3'.EX.'1'}")
  end

  test "get_table/3 gets table metadata with appId param" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/tables/tbl"
      assert conn.query_string == "appId=app"
      Req.Test.json(conn, %{"id" => "tbl", "name" => "Tasks"})
    end)

    assert {:ok, %{"id" => "tbl"}} = Quickbase.get_table(client(), "tbl", "app")
  end

  test "create_field/3 posts the field body with tableId param" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/fields"
      assert conn.query_string == "tableId=tbl"
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(raw) == %{"label" => "Status", "fieldType" => "text"}
      Req.Test.json(conn, %{"id" => 10, "label" => "Status"})
    end)

    assert {:ok, %{"id" => 10}} =
             Quickbase.create_field(client(), "tbl", %{"label" => "Status", "fieldType" => "text"})
  end

  test "download_file/5 gets the file bytes at the versioned path" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/files/tbl/1/6/0"
      Req.Test.text(conn, "raw-bytes")
    end)

    assert {:ok, "raw-bytes"} = Quickbase.download_file(client(), "tbl", 1, 6)
  end

  test "get_temp_token/2 gets a temporary token for a dbid" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/v1/auth/temporary/app"
      Req.Test.json(conn, %{"temporaryAuthorization" => "abc"})
    end)

    assert {:ok, %{"temporaryAuthorization" => "abc"}} = Quickbase.get_temp_token(client(), "app")
  end

  test "stream_records/2 pages until totalRecords reached" do
    agent = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      %{"options" => %{"skip" => skip, "top" => 2}} = Jason.decode!(raw)
      Agent.update(agent, &(&1 + 1))

      rows = for i <- (skip + 1)..min(skip + 2, 5), do: %{"3" => %{"value" => i}}

      Req.Test.json(conn, %{
        "data" => rows,
        "metadata" => %{"numRecords" => length(rows), "totalRecords" => 5}
      })
    end)

    values =
      client()
      |> Quickbase.stream_records(from: "tbl", top: 2)
      |> Enum.map(&Quickbase.value(&1, 3))

    assert values == [1, 2, 3, 4, 5]
    assert Agent.get(agent, & &1) == 3
  end
end
