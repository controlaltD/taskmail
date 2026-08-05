// Claude API hívások (sima `fetch`, nincs szükség SDK-ra).
//
// TERVEZÉSI ELV: az itteni függvények szándékosan egyszerű, tábla-független
// paramétereket kapnak (tárgy, szöveg, feladó) — nem adatbázissorokat. Így a
// levél előkeresése a hívó Edge Function felelőssége marad, ez a modul pedig
// bárhonnan újrahasználható, a `taskmail_` séma ismerete nélkül is.

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const MODEL = "claude-sonnet-4-5-20250929";

/**
 * Ennyi karakternél hosszabb levéltörzset levágunk. Egy hosszú levelezési
 * szál (idézett előzményekkel) tokenben drága, és a lényeg jellemzően a
 * legelején van — a levágás olcsóbb, mint a kérés kudarca.
 */
const MAX_BODY_CHARS = 12000;

function truncate(text: string, limit = MAX_BODY_CHARS): string {
  if (text.length <= limit) return text;
  return `${text.slice(0, limit)}\n\n[…a levél további része levágva]`;
}

interface AnthropicMessage {
  role: "user" | "assistant";
  content: string;
}

async function callClaude(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY nincs beállítva");

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({ model: MODEL, ...body }),
  });

  if (!res.ok) {
    throw new Error(`Claude API hiba (${res.status}): ${await res.text()}`);
  }
  return await res.json();
}

function toolResult<T>(data: Record<string, unknown>, toolName: string): T {
  const content = (data.content ?? []) as Array<{ type: string; input?: unknown }>;
  const toolUse = content.find((c) => c.type === "tool_use");
  if (!toolUse?.input) throw new Error(`Claude nem adott vissza ${toolName} választ`);
  return toolUse.input as T;
}

// ─── Levél kategorizálása (a szinkron használja) ───────────────────

export interface EmailClassification {
  category: "urgent" | "task" | "newsletter" | "other";
  summary: string;
  actionable: boolean;
  taskTitle?: string;
  taskDescription?: string;
  taskPriority?: "urgent" | "high" | "medium" | "low";
  taskDueDate?: string; // YYYY-MM-DD
}

const CLASSIFY_TOOL = {
  name: "classify_email",
  description: "Kategorizálja a beérkezett emailt, és ha van benne konkrét teendő, kinyeri azt.",
  input_schema: {
    type: "object",
    properties: {
      category: { type: "string", enum: ["urgent", "task", "newsletter", "other"] },
      summary: { type: "string", description: "1 mondatos magyar összefoglaló a levélről." },
      actionable: { type: "boolean", description: "Van-e a levélben konkrét, elvégzendő teendő." },
      taskTitle: { type: "string" },
      taskDescription: { type: "string" },
      taskPriority: { type: "string", enum: ["urgent", "high", "medium", "low"] },
      taskDueDate: { type: "string", description: "ISO dátum (YYYY-MM-DD), ha van határidő." },
    },
    required: ["category", "summary", "actionable"],
  },
};

export async function classifyEmail(params: {
  subject: string;
  snippet: string;
  fromAddress: string;
}): Promise<EmailClassification> {
  const data = await callClaude({
    max_tokens: 512,
    tools: [CLASSIFY_TOOL],
    tool_choice: { type: "tool", name: "classify_email" },
    messages: [
      {
        role: "user",
        content:
          `Kategorizáld az alábbi emailt, és ha van benne konkrét, elvégzendő teendő, ` +
          `nyerd ki egy feladat-javaslattá.\n\n` +
          `Feladó: ${params.fromAddress}\nTárgy: ${params.subject}\nRészlet: ${params.snippet}`,
      },
    ],
  });

  return toolResult<EmailClassification>(data, "classify_email");
}

// ─── Válaszjavaslat (az AI panel gombja kéri) ──────────────────────

export interface QuickReply {
  subject: string;
  bodyText: string;
}

const QUICK_REPLY_TOOL = {
  name: "draft_reply",
  description: "Rövid, udvarias válaszlevél-javaslatot fogalmaz a kapott levélre.",
  input_schema: {
    type: "object",
    properties: {
      subject: { type: "string", description: "A válasz tárgya (jellemzően 'Re: eredeti tárgy')." },
      bodyText: {
        type: "string",
        description:
          "A válasz szövege magyarul, megszólítással és elköszönéssel, 2-5 mondat. " +
          "Ne tartalmazzon kitöltendő helyőrzőt, ha a levélből kiderül a szükséges információ.",
      },
    },
    required: ["subject", "bodyText"],
  },
};

export async function suggestQuickReply(params: {
  subject: string;
  bodyText: string;
  fromAddress: string;
  fromName?: string | null;
}): Promise<QuickReply> {
  const sender = params.fromName ? `${params.fromName} <${params.fromAddress}>` : params.fromAddress;

  const data = await callClaude({
    max_tokens: 1024,
    tools: [QUICK_REPLY_TOOL],
    tool_choice: { type: "tool", name: "draft_reply" },
    messages: [
      {
        role: "user",
        content:
          `Fogalmazz rövid, udvarias magyar választ az alábbi levélre. A válasz legyen ` +
          `konkrét és felhasználható; ha a levél kérdést tartalmaz, arra reagálj.\n\n` +
          `Feladó: ${sender}\nTárgy: ${params.subject}\n\n${truncate(params.bodyText)}`,
      },
    ],
  });

  return toolResult<QuickReply>(data, "draft_reply");
}

// ─── Chat a levélről ───────────────────────────────────────────────

export async function chatAboutEmail(params: {
  subject: string;
  bodyText: string;
  fromAddress: string;
  userMessage: string;
  history: AnthropicMessage[];
}): Promise<string> {
  // A levél a rendszerüzenetbe kerül, nem a beszélgetésbe: így a felhasználó
  // kérdéseitől elkülönül, és a modell nem tudja "felülírni" a levél
  // tartalmát egy későbbi üzenettel.
  const system =
    `Egy levelezőalkalmazás beépített asszisztense vagy. A felhasználó éppen az ` +
    `alábbi levelet olvassa, és ezzel kapcsolatban kérdez. Válaszolj magyarul, ` +
    `tömören. Ha a válasz nem derül ki a levélből, mondd meg őszintén, hogy nem ` +
    `szerepel benne — ne találgass.\n\n` +
    `--- A LEVÉL ---\nFeladó: ${params.fromAddress}\nTárgy: ${params.subject}\n\n` +
    `${truncate(params.bodyText)}\n--- A LEVÉL VÉGE ---`;

  const data = await callClaude({
    max_tokens: 1024,
    system,
    messages: [...params.history, { role: "user", content: params.userMessage }],
  });

  const content = (data.content ?? []) as Array<{ type: string; text?: string }>;
  const text = content.filter((c) => c.type === "text").map((c) => c.text ?? "").join("").trim();
  if (!text) throw new Error("Claude üres választ adott");
  return text;
}
