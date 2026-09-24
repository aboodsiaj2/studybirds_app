import { useEffect, useState } from "react";
import { adminService } from "../../services/adminService";
import type { ServiceRequestItem } from "../../types";
import { useLanguage } from "../../hooks/useLanguage";
import { getErrorMessage } from "../../utils/errors";

const STATUS_LABELS: Record<string, { ar: string; en: string }> = {
  submitted: { ar: "مُرسَل", en: "Submitted" },
  "under-review": { ar: "قيد المراجعة", en: "Under Review" },
  "action-required": { ar: "إجراء مطلوب", en: "Action Required" },
  "awaiting-payment": { ar: "بانتظار الدفع", en: "Awaiting Payment" },
  "in-progress": { ar: "جارٍ التنفيذ", en: "In Progress" },
  completed: { ar: "مكتمل", en: "Completed" },
  rejected: { ar: "مرفوض", en: "Rejected" },
  cancelled: { ar: "ملغي", en: "Cancelled" },
};

const STATUSES_REQUIRING_REASON = ["action-required", "rejected", "cancelled"];

export const AdminServiceRequestsPage = () => {
  const { language } = useLanguage();
  const isArabic = language === "ar";
  const [items, setItems] = useState<ServiceRequestItem[]>([]);
  const [assignees, setAssignees] = useState<{ _id: string; name: string; email: string }[]>([]);
  const [statusFilter, setStatusFilter] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState<Record<string, boolean>>({});
  const [forms, setForms] = useState<Record<string, {
    nextStatus: string; reason: string; staffNote: string; amount: string; dueDate: string; assignedTo: string;
  }>>({});

  const load = (status?: string) => {
    adminService.getServiceRequests({ status: status || undefined })
      .then((data) => {
        setItems(data);
        setForms(data.reduce<typeof forms>((acc, item) => ({
          ...acc,
          [item._id]: { nextStatus: "", reason: "", staffNote: "", amount: "", dueDate: "", assignedTo: item.assignedTo?._id || "" },
        }), {}));
      })
      .catch((issue) => setError(getErrorMessage(issue, isArabic ? "تعذر تحميل الطلبات." : "Unable to load requests.")));
  };

  useEffect(() => {
    load(statusFilter || undefined);
    adminService.getServiceRequestAssignees().then(setAssignees).catch(() => {});
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isArabic, statusFilter]);

  const setForm = (id: string, patch: Partial<typeof forms[string]>) =>
    setForms((prev) => ({ ...prev, [id]: { ...prev[id], ...patch } }));

  const handleStatusUpdate = async (item: ServiceRequestItem) => {
    const form = forms[item._id];
    if (!form?.nextStatus) return;
    setBusy((prev) => ({ ...prev, [item._id]: true }));
    try {
      const updated = await adminService.updateServiceRequestStatus(item._id, {
        status: form.nextStatus,
        version: item.__v,
        reason: form.reason || undefined,
        staffNote: form.staffNote || undefined,
        amount: form.amount ? Number(form.amount) : undefined,
        dueDate: form.dueDate || undefined,
      });
      setItems((prev) => prev.map((r) => (r._id === item._id ? updated : r)));
      setForms((prev) => ({ ...prev, [item._id]: { ...prev[item._id], nextStatus: "", reason: "", staffNote: "", amount: "", dueDate: "" } }));
    } catch (issue) {
      alert(getErrorMessage(issue, isArabic ? "تعذر تحديث الحالة." : "Unable to update status."));
    } finally {
      setBusy((prev) => ({ ...prev, [item._id]: false }));
    }
  };

  const handleAssign = async (item: ServiceRequestItem) => {
    const form = forms[item._id];
    setBusy((prev) => ({ ...prev, [`assign-${item._id}`]: true }));
    try {
      const updated = await adminService.assignServiceRequest(item._id, {
        assignedTo: form.assignedTo || null,
        version: item.__v,
      });
      setItems((prev) => prev.map((r) => (r._id === item._id ? updated : r)));
    } catch (issue) {
      alert(getErrorMessage(issue, isArabic ? "تعذر تحديث المسؤول." : "Unable to update assignee."));
    } finally {
      setBusy((prev) => ({ ...prev, [`assign-${item._id}`]: false }));
    }
  };

  const statusBadge = (status: string) => {
    const label = STATUS_LABELS[status];
    const colors: Record<string, string> = {
      submitted: "bg-blue-100 text-blue-800",
      "under-review": "bg-yellow-100 text-yellow-800",
      "action-required": "bg-orange-100 text-orange-800",
      "awaiting-payment": "bg-purple-100 text-purple-800",
      "in-progress": "bg-sky-100 text-sky-800",
      completed: "bg-green-100 text-green-800",
      rejected: "bg-rose-100 text-rose-800",
      cancelled: "bg-slate-100 text-slate-600",
    };
    return (
      <span className={`rounded-full px-3 py-1 text-xs font-semibold ${colors[status] || "bg-slate-100 text-slate-600"}`}>
        {isArabic ? label?.ar : label?.en}
      </span>
    );
  };

  return (
    <div className="space-y-6">
      <section className="panel p-6">
        <h1 className="text-3xl font-semibold text-slate-900">{isArabic ? "طلبات الخدمات" : "Service Requests"}</h1>
        <p className="mt-2 text-sm text-slate-500">
          {isArabic ? "تابع طلبات الخدمات المقدمة من الطلاب وحرّك كل طلب عبر دورة حياته." : "Track student service requests and advance each through its lifecycle."}
        </p>
        <div className="mt-4 flex flex-wrap gap-2">
          {["", ...Object.keys(STATUS_LABELS)].map((s) => (
            <button key={s} type="button"
              onClick={() => setStatusFilter(s)}
              className={`rounded-full px-3 py-1 text-xs font-semibold transition ${statusFilter === s ? "bg-slate-950 text-white" : "bg-slate-100 text-slate-700 hover:bg-slate-200"}`}>
              {s === "" ? (isArabic ? "الكل" : "All") : (isArabic ? STATUS_LABELS[s]?.ar : STATUS_LABELS[s]?.en)}
            </button>
          ))}
        </div>
        {error ? <div className="mt-4 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">{error}</div> : null}
      </section>

      <div className="space-y-4">
        {items.length === 0 && !error && (
          <p className="rounded-3xl bg-slate-50 px-6 py-10 text-center text-sm text-slate-400">
            {isArabic ? "لا توجد طلبات" : "No requests found"}
          </p>
        )}
        {items.map((item) => {
          const form = forms[item._id] || { nextStatus: "", reason: "", staffNote: "", amount: "", dueDate: "", assignedTo: "" };
          const needsReason = STATUSES_REQUIRING_REASON.includes(form.nextStatus);
          const needsAmount = form.nextStatus === "awaiting-payment";
          return (
            <article key={item._id} className="panel p-6 space-y-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="text-xl font-semibold text-slate-900">{item.service?.title}</h2>
                  <p className="mt-1 text-sm text-slate-500">{item.student?.name} · {item.student?.email}</p>
                  {item.notes && <p className="mt-2 text-sm text-slate-600 italic">{item.notes}</p>}
                </div>
                {statusBadge(item.status)}
              </div>

              {item.reason && (
                <div className="rounded-2xl bg-orange-50 px-4 py-3 text-sm text-orange-800">
                  <span className="font-semibold">{isArabic ? "السبب: " : "Reason: "}</span>{item.reason}
                </div>
              )}
              {item.staffNote && (
                <div className="rounded-2xl bg-slate-50 px-4 py-3 text-sm text-slate-700">
                  <span className="font-semibold">{isArabic ? "ملاحظة الفريق: " : "Staff note: "}</span>{item.staffNote}
                </div>
              )}
              {item.studentReply && (
                <div className="rounded-2xl bg-blue-50 px-4 py-3 text-sm text-blue-800">
                  <span className="font-semibold">{isArabic ? "رد الطالب: " : "Student reply: "}</span>{item.studentReply}
                </div>
              )}
              {item.invoice && (
                <div className="rounded-2xl bg-purple-50 px-4 py-3 text-sm text-purple-800">
                  {isArabic ? "فاتورة" : "Invoice"}: {item.invoice.invoiceNumber} · {item.invoice.amount} · {item.invoice.status}
                </div>
              )}

              {/* Assign */}
              {(item.allowedStatuses?.length ?? 0) > 0 || true ? (
                <div className="flex flex-wrap items-center gap-3 border-t border-slate-100 pt-4">
                  <select
                    value={form.assignedTo}
                    onChange={(e) => setForm(item._id, { assignedTo: e.target.value })}
                    className="rounded-2xl border border-slate-200 px-4 py-2 text-sm outline-none focus:ring">
                    <option value="">{isArabic ? "— بدون مسؤول —" : "— Unassigned —"}</option>
                    {assignees.map((a) => <option key={a._id} value={a._id}>{a.name}</option>)}
                  </select>
                  <button type="button"
                    onClick={() => handleAssign(item)}
                    disabled={busy[`assign-${item._id}`]}
                    className="rounded-2xl bg-slate-800 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50">
                    {isArabic ? "تعيين" : "Assign"}
                  </button>
                  <span className="text-xs text-slate-400">{item.assignedTo ? `${isArabic ? "مسؤول: " : "Assigned: "}${item.assignedTo.name}` : (isArabic ? "غير مُسند" : "Unassigned")}</span>
                </div>
              ) : null}

              {/* Move status */}
              {(item.allowedStatuses?.length ?? 0) > 0 && (
                <div className="space-y-3 border-t border-slate-100 pt-4">
                  <div className="flex flex-wrap gap-3">
                    <select
                      value={form.nextStatus}
                      onChange={(e) => setForm(item._id, { nextStatus: e.target.value })}
                      className="rounded-2xl border border-slate-200 px-4 py-2 text-sm outline-none focus:ring">
                      <option value="">{isArabic ? "— اختر الحالة التالية —" : "— Choose next status —"}</option>
                      {(item.allowedStatuses || []).map((s) => (
                        <option key={s} value={s}>{isArabic ? STATUS_LABELS[s]?.ar : STATUS_LABELS[s]?.en}</option>
                      ))}
                    </select>
                  </div>
                  {needsReason && (
                    <textarea
                      rows={2}
                      placeholder={isArabic ? "السبب (يراه الطالب)" : "Reason (visible to student)"}
                      value={form.reason}
                      onChange={(e) => setForm(item._id, { reason: e.target.value })}
                      className="w-full rounded-2xl border border-slate-200 px-4 py-2 text-sm outline-none focus:ring"
                    />
                  )}
                  <textarea
                    rows={2}
                    placeholder={isArabic ? "ملاحظة داخلية (اختياري)" : "Internal note (optional)"}
                    value={form.staffNote}
                    onChange={(e) => setForm(item._id, { staffNote: e.target.value })}
                    className="w-full rounded-2xl border border-slate-200 px-4 py-2 text-sm outline-none focus:ring"
                  />
                  {needsAmount && (
                    <div className="flex gap-3">
                      <input
                        type="number"
                        min={0}
                        placeholder={isArabic ? "المبلغ" : "Amount"}
                        value={form.amount}
                        onChange={(e) => setForm(item._id, { amount: e.target.value })}
                        className="w-32 rounded-2xl border border-slate-200 px-4 py-2 text-sm outline-none focus:ring"
                      />
                      <input
                        type="date"
                        value={form.dueDate}
                        onChange={(e) => setForm(item._id, { dueDate: e.target.value })}
                        className="rounded-2xl border border-slate-200 px-4 py-2 text-sm outline-none focus:ring"
                      />
                    </div>
                  )}
                  <button
                    type="button"
                    onClick={() => handleStatusUpdate(item)}
                    disabled={!form.nextStatus || busy[item._id]}
                    className="rounded-2xl bg-slate-950 px-5 py-2 text-sm font-semibold text-white disabled:opacity-50">
                    {busy[item._id] ? (isArabic ? "جارٍ..." : "Saving…") : (isArabic ? "تحديث الحالة" : "Update Status")}
                  </button>
                </div>
              )}
            </article>
          );
        })}
      </div>
    </div>
  );
};
