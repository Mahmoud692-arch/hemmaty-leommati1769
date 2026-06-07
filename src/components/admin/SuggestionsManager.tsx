import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
} from "@/components/ui/dialog";
import { toast } from "sonner";
import { Lightbulb, CheckCircle2, XCircle, Clock, Eye } from "lucide-react";

interface Row {
  id: string;
  user_id: string;
  content_type: string;
  title: string;
  body: string;
  source: string | null;
  status: string;
  admin_notes: string | null;
  points_awarded: number;
  target_section: string | null;
  created_at: string;
}

export default function SuggestionsManager() {
  const [rows, setRows] = useState<Row[]>([]);
  const [filter, setFilter] = useState<"pending" | "approved" | "rejected" | "all">("pending");
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Row | null>(null);
  const [notes, setNotes] = useState("");
  const [section, setSection] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const load = async () => {
    setLoading(true);
    let q = supabase.from("content_suggestions").select("*").order("created_at", { ascending: false });
    if (filter !== "all") q = q.eq("status", filter);
    const { data } = await q;
    setRows((data ?? []) as Row[]);
    setLoading(false);
  };
  useEffect(() => { load(); }, [filter]);

  const review = async (approve: boolean) => {
    if (!selected) return;
    setSubmitting(true);
    const { error } = await supabase.rpc("admin_review_suggestion", {
      _id: selected.id,
      _approve: approve,
      _admin_notes: notes.trim() || null,
      _target_section: section.trim() || null,
    });
    setSubmitting(false);
    if (error) { toast.error(error.message || "تعذّر التحديث"); return; }
    toast.success(approve ? "تمت الموافقة ومنحت النقاط ✅" : "تم الرفض");
    setSelected(null); setNotes(""); setSection("");
    load();
  };

  const open = (r: Row) => {
    setSelected(r);
    setNotes(r.admin_notes ?? "");
    setSection(r.target_section ?? "");
  };

  return (
    <div>
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        <Lightbulb className="h-5 w-5 text-[var(--gold)]" />
        <h2 className="font-display text-lg">اقتراحات المستخدمين</h2>
        <div className="ms-auto flex gap-1">
          {(["pending", "approved", "rejected", "all"] as const).map((f) => (
            <Button key={f} size="sm" variant={filter === f ? "default" : "outline"} onClick={() => setFilter(f)}>
              {f === "pending" ? "قيد المراجعة" : f === "approved" ? "موافَق عليه" : f === "rejected" ? "مرفوض" : "الكل"}
            </Button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="text-center py-10 text-muted-foreground">جارٍ التحميل…</div>
      ) : rows.length === 0 ? (
        <div className="text-center py-10 text-muted-foreground rounded-xl border border-dashed">لا توجد اقتراحات</div>
      ) : (
        <div className="space-y-2">
          {rows.map((r) => (
            <div key={r.id} className="rounded-xl border p-3 flex items-start gap-3">
              <div className="shrink-0 mt-1">
                {r.status === "approved" ? <CheckCircle2 className="h-4 w-4 text-emerald-500" />
                  : r.status === "rejected" ? <XCircle className="h-4 w-4 text-red-500" />
                  : <Clock className="h-4 w-4 text-amber-500" />}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-medium truncate">{r.title}</span>
                  <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-muted">{r.content_type}</span>
                  {r.points_awarded > 0 && (
                    <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-[var(--gold)]/15 text-[var(--gold)]">+{r.points_awarded}</span>
                  )}
                </div>
                <div className="text-xs text-muted-foreground mt-1 line-clamp-2">{r.body}</div>
                <div className="text-[10px] text-muted-foreground mt-1" dir="ltr">{new Date(r.created_at).toLocaleString("ar-EG")}</div>
              </div>
              <Button size="sm" variant="outline" onClick={() => open(r)}>
                <Eye className="h-3 w-3 ms-1" /> مراجعة
              </Button>
            </div>
          ))}
        </div>
      )}

      <Dialog open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
        <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>مراجعة الاقتراح</DialogTitle>
          </DialogHeader>
          {selected && (
            <div className="space-y-3">
              <div className="rounded-xl border p-3">
                <div className="flex gap-2 items-center mb-2">
                  <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-muted">{selected.content_type}</span>
                  <span className="font-bold">{selected.title}</span>
                </div>
                <div className="text-sm whitespace-pre-wrap leading-relaxed max-h-64 overflow-y-auto">{selected.body}</div>
                {selected.source && (
                  <div className="text-xs text-muted-foreground mt-2">المصدر: {selected.source}</div>
                )}
              </div>
              <div>
                <Label className="mb-1.5 block">ملاحظة الأدمن (تظهر للمستخدم)</Label>
                <Textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} placeholder="اختياري — توضّح سبب القبول أو الرفض" />
              </div>
              <div>
                <Label className="mb-1.5 block">القسم المقترح للنشر <span className="text-muted-foreground text-xs">(اختياري)</span></Label>
                <Input value={section} onChange={(e) => setSection(e.target.value)} placeholder="مثلاً: مقالات / قصص الأنبياء" />
              </div>
              {selected.status !== "pending" && (
                <div className="text-xs text-amber-600">هذا الاقتراح روجِع بالفعل — لا يمكن تغيير قراره.</div>
              )}
            </div>
          )}
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setSelected(null)}>إغلاق</Button>
            {selected?.status === "pending" && (
              <>
                <Button variant="destructive" disabled={submitting} onClick={() => review(false)}>
                  <XCircle className="h-4 w-4 ms-1" /> رفض
                </Button>
                <Button disabled={submitting} onClick={() => review(true)}>
                  <CheckCircle2 className="h-4 w-4 ms-1" /> موافقة + منح النقاط
                </Button>
              </>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
