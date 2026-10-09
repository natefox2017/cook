// Developer: gengyun
// Purpose: Convert browser WebAuthn credentials to and from the server JSON contract.

type DescriptorJSON = { id: string; type?: "public-key"; transports?: AuthenticatorTransport[] };
type CreationJSON = {
  challenge: string;
  user: { id: string; name: string; displayName: string };
  excludeCredentials?: DescriptorJSON[];
  [key: string]: unknown;
};
type RequestJSON = {
  challenge: string;
  allowCredentials?: DescriptorJSON[];
  [key: string]: unknown;
};

function decode(value: string): Uint8Array<ArrayBuffer> {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const binary = atob(normalized + "=".repeat((4 - normalized.length % 4) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

function encode(value: ArrayBuffer): string {
  const bytes = new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function descriptor(item: DescriptorJSON): PublicKeyCredentialDescriptor {
  return {
    id: decode(item.id),
    type: "public-key",
    ...(item.transports ? { transports: item.transports } : {}),
  };
}

export async function createPasskey(options: Record<string, unknown>): Promise<Record<string, unknown>> {
  if (!navigator.credentials?.create) throw new Error("This browser does not support passkeys.");
  const parsed = options as CreationJSON;
  const credential = await navigator.credentials.create({
    publicKey: {
      ...parsed,
      challenge: decode(parsed.challenge),
      user: { ...parsed.user, id: decode(parsed.user.id) },
      ...(parsed.excludeCredentials ? { excludeCredentials: parsed.excludeCredentials.map(descriptor) } : {}),
    } as unknown as PublicKeyCredentialCreationOptions,
  });
  if (!(credential instanceof PublicKeyCredential)) throw new Error("Passkey setup was cancelled.");
  const response = credential.response as AuthenticatorAttestationResponse;
  return {
    id: credential.id,
    rawId: encode(credential.rawId),
    type: credential.type,
    authenticatorAttachment: credential.authenticatorAttachment,
    response: {
      clientDataJSON: encode(response.clientDataJSON),
      attestationObject: encode(response.attestationObject),
      transports: response.getTransports?.() ?? [],
    },
    clientExtensionResults: credential.getClientExtensionResults(),
  };
}

export async function getPasskeyCredential(options: Record<string, unknown>): Promise<Record<string, unknown>> {
  if (!navigator.credentials?.get) throw new Error("This browser does not support passkeys.");
  const parsed = options as RequestJSON;
  const credential = await navigator.credentials.get({
    publicKey: {
      ...parsed,
      challenge: decode(parsed.challenge),
      ...(parsed.allowCredentials ? { allowCredentials: parsed.allowCredentials.map(descriptor) } : {}),
    } as PublicKeyCredentialRequestOptions,
  });
  if (!(credential instanceof PublicKeyCredential)) throw new Error("Passkey sign-in was cancelled.");
  const response = credential.response as AuthenticatorAssertionResponse;
  return {
    id: credential.id,
    rawId: encode(credential.rawId),
    type: credential.type,
    authenticatorAttachment: credential.authenticatorAttachment,
    response: {
      clientDataJSON: encode(response.clientDataJSON),
      authenticatorData: encode(response.authenticatorData),
      signature: encode(response.signature),
      userHandle: response.userHandle ? encode(response.userHandle) : null,
    },
    clientExtensionResults: credential.getClientExtensionResults(),
  };
}
