// Claude API hívás (tool-use structured output) a levél kategorizálásához
// és a benne rejlő teendő kinyeréséhez. Sima `fetch`, nincs szükség SDK-ra.

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const MODEL = "claude-sonnet-4-5-20250929";

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
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY nincs beállítva");

  const res = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
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
    }),
  });

  if (!res.ok) {
    throw new Error(`Claude API hiba (${res.status}): ${await res.text()}`);
  }

  const data = await res.json();
  const toolUse = (data.content ?? []).find((c: { type: string }) => c.type === "tool_use");
  if (!toolUse) throw new Error("Claude nem adott vissza tool_use választ");

  return toolUse.input as EmailClassification;
}
