import { purgeUserStorage } from "./storage-purge.ts";

type Entry = { id: string | null; name: string };

class FakeStorageClient {
  readonly listCalls: Array<
    { bucket: string; prefix: string; offset: number }
  > = [];
  readonly removals: Array<{ bucket: string; paths: string[] }> = [];
  readonly entriesByPrefix = new Map<string, Entry[]>();
  listErrorPrefix?: string;
  removeError = false;

  storage = {
    from: (bucket: string) => ({
      list: async (
        prefix: string,
        options: { limit: number; offset: number },
      ) => {
        this.listCalls.push({ bucket, prefix, offset: options.offset });
        if (prefix === this.listErrorPrefix) {
          return { data: null, error: { message: "list failed" } };
        }
        const entries = this.entriesByPrefix.get(prefix) ?? [];
        return {
          data: entries.slice(options.offset, options.offset + options.limit),
          error: null,
        };
      },
      remove: async (paths: string[]) => {
        this.removals.push({ bucket, paths });
        return {
          error: this.removeError ? { message: "remove failed" } : null,
        };
      },
    }),
  };
}

function assertEqual(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

async function assertRejects(operation: () => Promise<void>): Promise<void> {
  try {
    await operation();
  } catch {
    return;
  }
  throw new Error("Expected operation to reject");
}

Deno.test("purges only the requested user's files, including nested folders", async () => {
  const client = new FakeStorageClient();
  client.entriesByPrefix.set("user-a", [
    { id: null, name: "imports" },
    { id: "file", name: "avatar.jpg" },
  ]);
  client.entriesByPrefix.set("user-a/imports", [
    { id: "file", name: "source.json" },
  ]);

  await purgeUserStorage(client, "user-a", ["avatars"]);

  assertEqual(
    client.listCalls.map(({ prefix }) => prefix),
    ["user-a", "user-a/imports"],
  );
  assertEqual(client.removals, [{
    bucket: "avatars",
    paths: ["user-a/imports/source.json", "user-a/avatar.jpg"],
  }]);
});

Deno.test("paginates listings and chunks removals at the API limit", async () => {
  const client = new FakeStorageClient();
  client.entriesByPrefix.set(
    "user-a",
    Array.from({ length: 201 }, (_, index) => ({
      id: "file",
      name: `file-${index}.jpg`,
    })),
  );

  await purgeUserStorage(client, "user-a", ["avatars"]);

  assertEqual(
    client.listCalls.map(({ offset }) => offset),
    [0, 100, 200],
  );
  assertEqual(client.removals.map(({ paths }) => paths.length), [100, 100, 1]);
  if (client.removals.flatMap(({ paths }) => paths).length !== 201) {
    throw new Error("Expected every listed file to be removed once");
  }
});

Deno.test("stops cleanup when listing or removal fails", async () => {
  const listFailure = new FakeStorageClient();
  listFailure.listErrorPrefix = "user-a";
  await assertRejects(() =>
    purgeUserStorage(listFailure, "user-a", ["one", "two"])
  );
  assertEqual(listFailure.removals, []);
  assertEqual(listFailure.listCalls.map(({ bucket }) => bucket), ["one"]);

  const removeFailure = new FakeStorageClient();
  removeFailure.entriesByPrefix.set("user-a", [{
    id: "file",
    name: "avatar.jpg",
  }]);
  removeFailure.removeError = true;
  await assertRejects(() =>
    purgeUserStorage(removeFailure, "user-a", ["one", "two"])
  );
  assertEqual(removeFailure.listCalls.map(({ bucket }) => bucket), ["one"]);
});
