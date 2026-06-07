import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "sonner";
import { ArrowRight, Lightbulb, CheckCircle2, Clock, XCircle } from "lucide-react";

export const Route = createFileRoute("/me/suggest")({
  component: SuggestPage,
  head: () => ({ meta: [{ title: "اقترح محتوى | همّتي لأمتي" }] }),
});

interface Row {
  id: string;
  content_type: string;
  title: string;
  status: string;
  admin_notes: string | null;
  points_awarded: number;
  created_at: string;
}

function SuggestPage() {
  const { user, loading } = useAuth();
  const navigate = useNavigate();
  const [type, setType] = useState("article");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [source, setSource] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [rows, setRows] = useState<Row[]>([]);
  const [rewardPoints, setRewardPoints] = useState(50);

  useEffect(() => {
    if (!loading && !user) navigate({ to: "/auth" });
  }, [loading, user, navigate]);

  const load = async () => {
    if (!user) return;
    const [{ data }, { data: setting }] = await Promise.all([
      supabase
        .from("content_suggestions")
        .select("id, content_type, title, status, admin_notes, points_awarded, created_at")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false }),
      supabase.from("public_site_settings").select("value").eq("key", "suggestion_reward_points").maybeSingle(),
    ]);
    setRows((data ?? []) as Row[]);
    if (setting?.value != null) setRewardPoints(Number(setting.value) || 50);
  };

  useEffect(() => { load(); }, [user]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (title.trim().length < 3) { toast.error("العنوان قصير جداً"); return; }
    if (body.trim().length < 20) { toast.error("النص قصير جداً (20 حرف على الأقل)"); return; }
    setSubmitting(true);
    const { error } = await supabase.rpc("submit_suggestion", {
      _content_type: type,
      _title: title.trim(),
      _body: body.trim(),
      _source: source.trim() || null,
    });
    setSubmitting(false);
    if (error) { toast.error(error.message || "تعذّر الإرسال"); return; }
    toast.success("تم إرسال اقتراحك للمراجعة 🌟");
    setTitle(""); setBody(""); setSource("");
    load();
  };

  if (loading || !user) return <div className="container mx-auto px-4 py-12 text-center text-muted-foreground">جارٍ التحميل…</div>;

  return (
    <div className="container mx-auto px-4 py-12 max-w-3xl">
      <Link to="/me" className="inline-flex items-center gap-1.5 text-sm text-muted-foreground hover:text-primary mb-6">
        <ArrowRight className="h-4 w-4" /> العودة لملفي
      </Link>

      <div className="rounded-2xl border bg-gradient-to-bl from-[var(--gold)]/10 to-transparent p-6 mb-8">
        <div className="flex items-start gap-3">
          <Lightbulb className="h-6 w-6 text-[var(--gold)] shrink-0 mt-1" />
          <div>
            <h1 className="font-display text-2xl mb-2">اقترح محتوى للمنصة</h1>
            <p className="text-sm text-muted-foreground leading-relaxed">
              شاركنا مقالاً، حديثاً، قصة، أو اقتباساً ترى أنه يستحق النشر. عند الموافقة، تحصل على
              <span className="text-[var(--gold)] font-bold mx-1">+{rewardPoints} نقطة</span>
              ويُنشر باسم المنصة.
            </p>
          </div>
        </div>
      </div>

      <form onSubmit={submit} className="space-y-4 rounded-2xl border p-6 bg-card">
        <div>
          <Label className="mb-1.5 block">نوع المحتوى</Label>
          <Select value={type} onValueChange={setType}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="article">مقال</SelectItem>
              <SelectItem value="hadith">حديث</SelectItem>
              <SelectItem value="story">قصة</SelectItem>
              <SelectItem value="quote">اقتباس / حكمة</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div>
          <Label className="mb-1.5 block">العنوان</Label>
          <Input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={250} placeholder="عنوان واضح ومختصر" required />
        </div>
        <div>
          <Label className="mb-1.5 block">النص</Label>
          <Textarea value={body} onChange={(e) => setBody(e.target.value)} maxLength={20000} rows={10} placeholder="اكتب المحتوى كاملاً هنا…" required />
          <div className="text-[11px] text-muted-foreground mt-1">{body.length} / 20000</div>
        </div>
        <div>
          <Label className="mb-1.5 block">المصدر <span className="text-muted-foreground">(اختياري)</span></Label>
          <Input value={source} onChange={(e) => setSource(e.target.value)} maxLength={500} placeholder="رابط، كتاب، شيخ، صحيح البخاري..." />
        </div>
        <Button type="submit" disabled={submitting} className="w-full">
          {submitting ? "جارٍ الإرسال…" : "إرسال للمراجعة"}
        </Button>
      </form>

      <div className="mt-10">
        <h2 className="font-display text-xl mb-4">اقتراحاتي السابقة</h2>
        {rows.length === 0 ? (
          <div className="text-center py-10 text-muted-foreground rounded-xl border border-dashed">لا توجد اقتراحات بعد</div>
        ) : (
          <div className="space-y-2">
            {rows.map((r) => (
              <div key={r.id} className="rounded-xl border p-3 text-sm flex items-start gap-3">
                <div className="shrink-0 mt-1">
                  {r.status === "approved" ? <CheckCircle2 className="h-4 w-4 text-emerald-500" />
                    : r.status === "rejected" ? <XCircle className="h-4 w-4 text-red-500" />
                    : <Clock className="h-4 w-4 text-amber-500" />}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium truncate">{r.title}</span>
                    <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-muted">{r.content_type}</span>
                    {r.status === "approved" && r.points_awarded > 0 && (
                      <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-[var(--gold)]/15 text-[var(--gold)]">+{r.points_awarded} نقطة</span>
                    )}
                  </div>
                  {r.admin_notes && <div className="text-xs text-muted-foreground mt-1">ملاحظة الأدمن: {r.admin_notes}</div>}
                  <div className="text-[10px] text-muted-foreground mt-1" dir="ltr">{new Date(r.created_at).toLocaleString("ar-EG")}</div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
