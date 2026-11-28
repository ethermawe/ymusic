// TypeScript definitions for ymusic Logic Mods API (v1.0)

export type HookPoint =
  | "search_results"
  | "wave_next_batch"
  | "queue_before_add"
  | "track_before_play"
  | "track_after_play"
  | "lyrics_loaded"
  | "playlist_loaded"
  | "album_loaded"
  | "scrobble_before";

export interface HookCancelToken {
  readonly __ymCancel: true;
  readonly reason: string;
}

export type HookHandler<T = Record<string, unknown>> = (
  payload: T
) => T | HookCancelToken | void | Promise<T | HookCancelToken | void>;

export interface TrackSummary {
  id: string;
  title: string;
  artists: string;
  album: string;
  durationMs?: number;
  available?: boolean;
  liked?: boolean;
  explicit?: boolean;
  coverUrl?: string;
}

export interface HttpRequestOptions {
  headers?: Record<string, string>;
  body?: string;
}

export interface HttpResponse {
  status: number;
  body: string;
  error: string;
}

export interface CommandOptions {
  shortcut?: string;
}

export interface PageRegistration {
  title: string;
  icon?: string;
  qml: string;
}

export interface SettingFieldSchema {
  type: "boolean" | "string" | "number" | "select";
  title: string;
  default?: unknown;
  options?: string[];
}

export type SettingsSchema = Record<string, SettingFieldSchema>;

export interface YmApi {
  cancel(reason?: string): HookCancelToken;

  hooks: {
    on<T = Record<string, unknown>>(point: HookPoint, fn: HookHandler<T>): boolean;
    off<T = Record<string, unknown>>(point: HookPoint, fn: HookHandler<T>): void;
  };

  events: {
    on(
      name: "trackChanged" | "playbackChanged" | "queueChanged" | "liked" | "loggedIn",
      fn: (data: Record<string, unknown>) => void
    ): void;
    off(name: string, fn: (data: Record<string, unknown>) => void): void;
  };

  player: {
    toggle(): boolean;
    next(): boolean;
    prev(): boolean;
    seek(progress: number): boolean;
    queue(): TrackSummary[];
    addToQueue(trackId: string): boolean;
    playNext(trackId: string): boolean;
  };

  library: {
    history(): TrackSummary[];
    playlists(): Record<string, unknown>[];
  };

  commands: {
    register(id: string, title: string, fn: () => void, opts?: CommandOptions): boolean;
  };

  settings: {
    define(schema: SettingsSchema): void;
    get<T = unknown>(key: string, fallback?: T): T;
    set(key: string, value: unknown): boolean;
    onChange(fn: (key: string, value: unknown) => void): void;
  };

  pages: {
    register(id: string, opts: PageRegistration): boolean;
  };

  storage: {
    get<T = unknown>(key: string, fallback?: T): T;
    set(key: string, value: unknown): boolean;
    remove(key: string): boolean;
    all(): Record<string, unknown>;
  };

  http: {
    request(method: string, url: string, opts?: HttpRequestOptions): Promise<HttpResponse>;
  };

  ui: {
    toast(message: string): boolean;
    notify(title: string, body?: string): boolean;
    expose(name: string, fn: (...args: unknown[]) => unknown): void;
    post(message: unknown): void;
  };

  exports: Record<string, unknown>;
  require<T = Record<string, unknown>>(modId: string): T | undefined;
}

declare global {
  const ym: YmApi;
}

export declare function activate(ym: YmApi): void;
export declare function deactivate(): void;
