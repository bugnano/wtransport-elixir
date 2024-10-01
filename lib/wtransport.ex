defmodule Wtransport do
  defmodule SessionRequest do
    use TypedStruct

    typedstruct do
      field(:authority, String.t(), enforce: true)
      field(:path, String.t(), enforce: true)
      field(:origin, String.t(), enforce: true)
      field(:user_agent, String.t(), enforce: true)
      field(:headers, %{String.t() => String.t()}, enforce: true)
      field(:request_tx, reference(), enforce: true)
    end
  end

  defmodule Session do
    use TypedStruct

    typedstruct do
      field(:authority, String.t(), enforce: true)
      field(:path, String.t(), enforce: true)
      field(:origin, String.t(), enforce: true)
      field(:user_agent, String.t(), enforce: true)
      field(:headers, %{String.t() => String.t()}, enforce: true)
    end
  end

  defmodule ConnectionRequest do
    use TypedStruct

    typedstruct do
      field(:stable_id, non_neg_integer(), enforce: true)
      field(:send_dgram_tx, reference(), enforce: true)
    end
  end

  defmodule StreamRequest do
    use TypedStruct

    typedstruct do
      field(:stream_type, :bi | :uni, enforce: true)
      field(:request_tx, reference(), enforce: true)
      field(:write_all_tx, reference(), enforce: true)
    end
  end
end
