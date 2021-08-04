defmodule Boruta.Oauth.IdToken do
  defmodule Token do
    @moduledoc false

    use Joken.Config

    def token_config, do: %{}
  end

  import Boruta.Config, only: [resource_owners: 0, issuer: 0]

  alias Boruta.Oauth

  @signature_alg "RS512"
  @hash_alg :sha512

  @type tokens :: %{
          optional(:code) => %Oauth.Token{
            sub: String.t(),
            client: Oauth.Client.t(),
            inserted_at: DateTime.t(),
            scope: String.t()
          },
          optional(:token) => %Oauth.Token{
            sub: String.t(),
            client: Oauth.Client.t(),
            inserted_at: DateTime.t(),
            scope: String.t()
          },
          optional(:base_token) => %Oauth.Token{
            sub: String.t(),
            client: Oauth.Client.t(),
            inserted_at: DateTime.t(),
            scope: String.t()
          }
        }

  @spec generate(tokens :: tokens(), nonce :: String.t()) :: id_token :: Oauth.Token.t()
  def generate(tokens, nonce) do
    {base_token, payload} = payload(tokens, nonce, %{})

    value = sign(payload, base_token.client.private_key)
    %{base_token | type: "id_token", value: value}
  end

  defp payload(%{code: code} = tokens, nonce, acc) do
    tokens
    |> Map.put(:base_token, code)
    |> Map.delete(:code)
    |> payload(nonce, Map.put(acc, "c_hash", hash(code.value)))
  end

  defp payload(%{token: token} = tokens, nonce, acc) do
    tokens
    |> Map.put(:base_token, token)
    |> Map.delete(:token)
    |> payload(nonce, Map.put(acc, "at_hash", hash(token.value)))
  end

  defp payload(%{base_token: base_token}, nonce, acc) do
    {base_token, Map.merge(acc, payload(base_token, nonce))}
  end

  defp payload(
         %Oauth.Token{
           sub: sub,
           client: client,
           inserted_at: inserted_at,
           scope: scope
         },
         nonce
       ) do
    iat = DateTime.to_unix(inserted_at)

    resource_owners().claims(sub, scope)
    |> Map.put("sub", sub)
    |> Map.put("iss", issuer())
    |> Map.put("aud", client.id)
    |> Map.put("iat", iat)
    |> Map.put("auth_time", iat)
    |> Map.put("exp", iat + client.id_token_ttl)
    |> Map.put("nonce", nonce)
  end

  defp sign(payload, private_key) do
    signer = Joken.Signer.create(@signature_alg, %{"pem" => private_key})

    with {:ok, token, _payload} <- Token.encode_and_sign(payload, signer) do
      token
    end
  end

  defp hash(string) do
    :crypto.hash(@hash_alg, string)
    |> binary_part(0, 32)
    |> Base.url_encode64()
    |> String.replace("=", "")
  end
end
