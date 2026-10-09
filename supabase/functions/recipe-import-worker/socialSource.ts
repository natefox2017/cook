// Developer: gengyun
// Purpose: Recognizes public social URL identities without fetching video media.

export function publicSocialSourceIdentity(raw: string):
  { platform: "youtube" | "instagram" | "tiktok"; id: string } | null {
  let u: URL;
  try { u = new URL(raw); } catch { return null; }
  if (u.protocol !== "https:" || u.username || u.password || u.port) return null;
  const host = u.hostname.toLowerCase();
  const path = u.pathname.split("/").filter(Boolean);
  const isHost = (root: string): boolean =>
    host === root || host.endsWith("." + root);
  const yt = /^[A-Za-z0-9_-]{11}$/;
  const ig = /^[A-Za-z0-9_-]{5,32}$/;
  const tt = /^[0-9]{8,30}$/;
  if (host === "youtu.be" && path.length === 1 && yt.test(path[0])) {
    return { platform: "youtube", id: path[0] };
  }
  if (isHost("youtube.com")) {
    const id = u.pathname === "/watch" ? u.searchParams.get("v")
      : path.length === 2 && ["shorts", "live", "embed"].includes(path[0])
      ? path[1] : null;
    if (id && yt.test(id)) return { platform: "youtube", id };
  }
  if (isHost("instagram.com") && path.length === 2 &&
      ["p", "reel", "tv"].includes(path[0]) && ig.test(path[1])) {
    return { platform: "instagram", id: path[1] };
  }
  if (isHost("tiktok.com") && path.length === 3 && path[1] === "video" &&
      /^@[A-Za-z0-9._]{2,32}$/.test(path[0]) && tt.test(path[2])) {
    return { platform: "tiktok", id: path[2] };
  }
  return null;
}
