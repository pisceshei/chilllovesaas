import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { MediaCard } from "./MediaCard";
import type { MediaCardItem } from "./MediaCard";
import { I18nProvider } from "../i18n/I18nContext";
import { ToastProvider } from "../lib/ToastContext";

/**
 * 媒體卡（第 27 包）。三步直傳的前端契約（簽發→multipart→掛商品）在此釘住——
 * 那是第 25/27 包後端的第一個前端呼叫者，形狀錯了只有這裡會紅。
 */
function installCsrfMeta() {
  const meta = document.createElement("meta");
  meta.name = "csrf-token";
  meta.content = "csrf-test-token";
  document.head.append(meta);
}

function jsonResponse(body: unknown) {
  return { json: vi.fn().mockResolvedValue(body), ok: true, status: 200 } as unknown as Response;
}

const READY_ITEM: MediaCardItem = {
  id: "gid://chilllove/Media/1", position: 1, alt: "貓", status: "READY",
  image: { thumbUrl: "/admin/files/7/blob?variant=thumb", url: "/admin/files/7/blob" },
};
const PROCESSING_ITEM: MediaCardItem = {
  id: "gid://chilllove/Media/2", position: 2, alt: null, status: "PROCESSING",
  image: { thumbUrl: null, url: "/admin/files/8/blob" },
};

function renderCard(overrides: Partial<Parameters<typeof MediaCard>[0]> = {}) {
  const onReorder = vi.fn();
  const onRefresh = vi.fn();
  render(
    <I18nProvider initialLocale="zh-Hant">
      <ToastProvider>
        <MediaCard
          maxMedia={250}
          media={[ READY_ITEM, PROCESSING_ITEM ]}
          onRefresh={onRefresh}
          onReorder={onReorder}
          productGid="gid://chilllove/Product/9"
          {...overrides}
        />
      </ToastProvider>
    </I18nProvider>,
  );
  return { onReorder, onRefresh };
}

describe("媒體卡", () => {
  beforeEach(() => installCsrfMeta());

  it("首格標「精選」；處理中不顯示圖片而顯示占位（不得拿原圖冒充縮圖）", () => {
    renderCard();
    expect(screen.getByText("精選")).toBeVisible();
    const image = screen.getByRole("img", { name: "貓" });
    expect(image).toHaveAttribute("src", "/admin/files/7/blob?variant=thumb");
    expect(screen.getByText("處理中…")).toBeVisible();
    // 處理中那格沒有 <img>
    expect(screen.getAllByRole("img")).toHaveLength(1);
  });

  it("🔴 上傳走三步：stagedUploadsCreate → multipart POST → productCreateMedia", async () => {
    const calls: { url: string; body: unknown }[] = [];
    const fetchMock = vi.fn(async (url: unknown, init?: RequestInit) => {
      const endpoint = String(url);
      if (endpoint.includes("graphql")) {
        const request = JSON.parse(String(init?.body)) as { query: string };
        calls.push({ url: endpoint, body: request.query });
        if (request.query.includes("stagedUploadsCreate")) {
          return jsonResponse({
            data: {
              stagedUploadsCreate: {
                stagedTargets: [ {
                  url: "/admin/uploads/staged",
                  resourceUrl: "https://x.test/admin/uploads/staged-blob/shops/1/staged/u/a.png",
                  parameters: [ { name: "key", value: "shops/1/staged/u/a.png" },
                                { name: "signature", value: "sig" } ],
                } ],
                userErrors: [],
              },
            },
          });
        }
        return jsonResponse({ data: { productCreateMedia: { media: [ { id: "x" } ], userErrors: [] } } });
      }
      calls.push({ url: endpoint, body: init?.body });
      return jsonResponse({ resourceUrl: "https://x.test/blob" });
    });
    vi.stubGlobal("fetch", fetchMock);

    const { onRefresh } = renderCard({ media: [] });
    const user = userEvent.setup();
    const file = new File([ "PNGDATA" ], "貓咪.png", { type: "image/png" });
    await user.upload(screen.getByLabelText("上傳新檔案"), file);

    await waitFor(() => expect(onRefresh).toHaveBeenCalled());
    expect(calls).toHaveLength(3);
    expect(String(calls[0].body)).toContain("stagedUploadsCreate");
    // 第 2 步：multipart 到簽發回傳的 url，簽名參數原樣回送
    expect(calls[1].url).toBe("/admin/uploads/staged");
    const form = calls[1].body as FormData;
    expect(form.get("key")).toBe("shops/1/staged/u/a.png");
    expect(form.get("signature")).toBe("sig");
    expect((form.get("file") as File).name).toBe("貓咪.png");
    // 第 3 步：掛商品
    expect(String(calls[2].body)).toContain("productCreateMedia");
  });

  it("拖曳排序把新順序交給父層（不立即寫 DB——隨儲存送出）", () => {
    const { onReorder } = renderCard();
    const tiles = screen.getAllByRole("listitem");
    // 🔴 用 fireEvent 而非 dispatchEvent(new Event(...))：React 監聽的是合成事件，
    //    原生 Event 觸發不到 onDragStart／onDrop（實測）。
    fireEvent.dragStart(tiles[1]);
    fireEvent.drop(tiles[0], { dataTransfer: { files: [] } });

    expect(onReorder).toHaveBeenCalledWith([ PROCESSING_ITEM.id, READY_ITEM.id ]);
  });

  it("🔴 刪除先過確認框，文案說明共用檔保留；取消＝零請求", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      jsonResponse({ data: { productDeleteMedia: { deletedMediaIds: [], userErrors: [] } } }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const { onRefresh } = renderCard();
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "移除第 1 張圖" }));
    const dialog = screen.getByRole("dialog");
    expect(dialog).toHaveTextContent("共用的檔案保留");
    await user.click(screen.getByRole("button", { name: "取消" }));
    expect(fetchMock).not.toHaveBeenCalled();
    expect(onRefresh).not.toHaveBeenCalled();

    await user.click(screen.getByRole("button", { name: "移除第 1 張圖" }));
    await user.click(screen.getByRole("button", { name: "移除圖片" }));
    await waitFor(() => expect(onRefresh).toHaveBeenCalled());
    expect(String((fetchMock.mock.calls[0][1] as RequestInit).body)).toContain("productDeleteMedia");
  });

  // ── 第 37 包：外嵌影片 ────────────────────────────────────────────
  const VIDEO_ITEM = {
    id: "gid://chilllove/Media/5", position: 3, alt: "示範影片", status: "READY",
    image: null,
    externalVideo: {
      host: "YOUTUBE" as const, externalId: "dQw4w9WgXcQ",
      embedUrl: "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
      originUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    },
  };

  it("🔴 貼 URL 外嵌影片：送出 EXTERNAL_VIDEO，而不是走上傳", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse({
      data: { productCreateMedia: { media: [ { id: "gid://chilllove/Media/5" } ], userErrors: [] } },
    }));
    vi.stubGlobal("fetch", fetchMock);
    const { onRefresh } = renderCard();
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "嵌入影片" }));
    await user.type(screen.getByLabelText("影片網址"), "https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    await user.click(screen.getByRole("button", { name: "加入影片" }));

    await waitFor(() => expect(onRefresh).toHaveBeenCalled());
    const body = String((fetchMock.mock.calls[0][1] as RequestInit).body);
    expect(body).toContain("productCreateMedia");
    expect(body).toContain("EXTERNAL_VIDEO");
    // 🔴 前端**不驗 URL 形態**：判準只有一份、在後端。前端再寫一套 regex，
    //    兩份判準遲早漂移，而症狀是「前端說不行、後端其實可以」這種查不出來的假錯誤。
    expect(body).toContain("watch?v=dQw4w9WgXcQ");
  });

  it("🔴 伺服器的錯誤顯示在欄位旁而不是 toast（貼錯網址是要就地改的）", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({
      data: { productCreateMedia: { media: [], userErrors: [
        { field: [ "media", "0", "originalSource" ], message: "外嵌影片目前只支援 YouTube 與 Vimeo。",
          code: "EXTERNAL_VIDEO_UNSUPPORTED_HOST" } ] } },
    })));
    const { onRefresh } = renderCard();
    const user = userEvent.setup();

    await user.click(screen.getByRole("button", { name: "嵌入影片" }));
    await user.type(screen.getByLabelText("影片網址"), "https://dailymotion.com/video/x1");
    await user.click(screen.getByRole("button", { name: "加入影片" }));

    expect(await screen.findByText("外嵌影片目前只支援 YouTube 與 Vimeo。")).toBeVisible();
    // 失敗不關 modal——關掉的話使用者剛打的網址就沒了，要重貼一次
    expect(screen.getByRole("dialog")).toBeVisible();
    expect(onRefresh).not.toHaveBeenCalled();
  });

  it("🔴 外嵌影片的格子顯示平台名，不是永遠不會結束的「處理中」", () => {
    vi.stubGlobal("fetch", vi.fn());
    renderCard({ media: [ VIDEO_ITEM ] });
    expect(screen.getByText("YouTube")).toBeVisible();
    expect(screen.queryByText("處理中")).toBeNull();
  });

  it("空網址時「加入影片」不可按", async () => {
    vi.stubGlobal("fetch", vi.fn());
    renderCard();
    const user = userEvent.setup();
    await user.click(screen.getByRole("button", { name: "嵌入影片" }));
    expect(screen.getByRole("button", { name: "加入影片" })).toBeDisabled();
  });

  it("建立態（尚未有商品 GID）：只提示先儲存，不給上傳入口", () => {
    renderCard({ productGid: null, media: [] });
    expect(screen.getByText("先儲存商品，之後才能在這裡加圖片。")).toBeVisible();
    expect(screen.queryByRole("button", { name: "上傳新檔案" })).toBeNull();
  });
});
