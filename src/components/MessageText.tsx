/** A reply's text, with "a | b | c" tables drawn as real tables. */

type Block = { kind: "text"; text: string } | { kind: "table"; head: string[]; rows: string[][] };

/** The cells of a table row ("| a | b |" or "a | b"), or undefined if it isn't one. */
function cells(line: string): string[] | undefined {
  const t = line.trim();
  if (!t.includes("|")) return undefined;
  const parts = t.replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());
  return parts.length >= 2 ? parts : undefined;
}

/** "|---|:---:|" between a markdown table's header and its rows. */
const isSeparator = (row: string[]) => row.every((c) => /^:?-{3,}:?$/.test(c));

/**
 * Splits text into plain runs and tables. A table is two or more lines in a
 * row with the same number of "|"-separated cells; the first is the header.
 * Lines inside ``` fences stay as text.
 */
export function parseBlocks(text: string): Block[] {
  const lines = text.split("\n");
  const blocks: Block[] = [];
  let plain: string[] = [];
  let fenced = false;
  const flush = () => {
    if (plain.length) blocks.push({ kind: "text", text: plain.join("\n") });
    plain = [];
  };

  for (let i = 0; i < lines.length; ) {
    if (lines[i].trim().startsWith("```")) fenced = !fenced;
    const head = fenced ? undefined : cells(lines[i]);
    if (head) {
      const rows: string[][] = [];
      let j = i + 1;
      for (; j < lines.length; j++) {
        const row = cells(lines[j]);
        if (!row || row.length !== head.length) break;
        if (j === i + 1 && isSeparator(row)) continue;
        rows.push(row);
      }
      if (rows.length > 0 && !isSeparator(head)) {
        // Drop the blank line before a table; the table has its own spacing.
        if (plain.length && plain[plain.length - 1].trim() === "") plain.pop();
        flush();
        blocks.push({ kind: "table", head, rows });
        i = j;
        // ...and the blank line after it.
        if (i < lines.length && lines[i].trim() === "") i++;
        continue;
      }
    }
    plain.push(lines[i]);
    i++;
  }
  flush();
  return blocks;
}

const strip = (cell: string) => cell.replace(/^\*\*(.*)\*\*$/, "$1").replace(/^`(.*)`$/, "$1");

export function MessageText({ text }: { text: string }) {
  const blocks = parseBlocks(text);
  return (
    <div className="flex flex-col gap-2.5">
      {blocks.map((b, i) =>
        b.kind === "text" ? (
          <p key={i} className="selectable text-[14px] leading-[21px] break-words whitespace-pre-wrap text-ink">
            {b.text}
          </p>
        ) : (
          <div key={i} className="overflow-x-auto rounded-lg border border-modal-line bg-surface">
            <table className="selectable w-full border-collapse text-left text-[13px] leading-[19px] text-ink">
              <thead>
                <tr>
                  {b.head.map((c, k) => (
                    <th key={k} className="border-b border-modal-line px-3 py-2 font-semibold whitespace-nowrap text-subtle">
                      {strip(c)}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {b.rows.map((row, r) => (
                  <tr key={r} className={r < b.rows.length - 1 ? "border-b border-modal-line" : ""}>
                    {row.map((c, k) => (
                      <td key={k} className="px-3 py-2 align-top">
                        {strip(c)}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ),
      )}
    </div>
  );
}
