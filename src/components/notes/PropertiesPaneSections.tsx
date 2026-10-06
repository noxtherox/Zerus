import { useId, type ReactNode } from "react";
import { DndContext, KeyboardSensor, PointerSensor, closestCenter, useSensor, useSensors } from "@dnd-kit/core";
import { SortableContext, arrayMove, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { ArrowDown, ArrowUp, ChevronDown, ChevronRight, Ellipsis, GripVertical } from "@/lib/icons";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { DEFAULT_PROPERTIES_PANE_LAYOUT, PROPERTIES_PANE_LABELS, type PropertiesPaneSection } from "@/lib/properties-pane";
import { updatePropertiesPaneLayout, useVaultSelector } from "@/store/notes-store";

function Section({ id, collapsed, disabled, first, last, settings, onToggle, onMove, children }: {
  id: PropertiesPaneSection; collapsed: boolean; disabled: boolean; first: boolean; last: boolean;
  settings: boolean; onToggle: () => void; onMove: (direction: -1 | 1) => void; children?: ReactNode;
}) {
  const contentId = useId();
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, transform, transition, isDragging } = useSortable({ id, disabled });
  const label = PROPERTIES_PANE_LABELS[id];
  return <section ref={setNodeRef} data-properties-section={id} aria-label={label}
    className="relative shrink-0 border-b border-border/60 bg-inherit"
    style={{ transform: CSS.Transform.toString(transform), transition, zIndex: isDragging ? 10 : undefined, opacity: isDragging ? 0.65 : undefined }}>
    <div className="flex items-center gap-1 px-2 py-2">
      <Button ref={setActivatorNodeRef} variant="ghost" size="icon" className="h-8 w-6 shrink-0 touch-none cursor-grab text-muted-foreground active:cursor-grabbing"
        {...attributes} {...listeners} aria-label={`Reorder ${label}`} title="Drag to reorder; use Space and arrow keys with a keyboard" disabled={disabled}>
        <GripVertical size={13} />
      </Button>
      <button type="button" className="flex min-h-8 min-w-0 flex-1 items-center gap-1.5 text-left text-xs font-semibold uppercase tracking-wider text-muted-foreground"
        aria-label={`${collapsed ? "Expand" : "Collapse"} ${label}`} aria-expanded={!collapsed} aria-controls={settings ? undefined : contentId}
        disabled={disabled} onClick={onToggle}>
        {collapsed ? <ChevronRight size={13} className="shrink-0" /> : <ChevronDown size={13} className="shrink-0" />}
        <span className="truncate">{label}</span>
        {settings && <span className="ml-auto text-[11px] font-normal normal-case tracking-normal">{collapsed ? "Collapsed" : "Expanded"}</span>}
      </button>
      <DropdownMenu>
        <DropdownMenuTrigger asChild><Button variant="ghost" size="icon" className="h-8 w-8 shrink-0 text-muted-foreground" aria-label={`${label} section options`} disabled={disabled}><Ellipsis size={14} /></Button></DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem disabled={first} onSelect={() => onMove(-1)}><ArrowUp size={14} className="mr-2" />Move up</DropdownMenuItem>
          <DropdownMenuItem disabled={last} onSelect={() => onMove(1)}><ArrowDown size={14} className="mr-2" />Move down</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </div>
    {!settings && <div id={contentId} hidden={collapsed}>{children}</div>}
  </section>;
}

/** Both editing surfaces use the same layout, including sections absent from a particular note. */
export function PropertiesPaneSections({ sections }: { sections?: Partial<Record<PropertiesPaneSection, ReactNode>> }) {
  const layout = useVaultSelector((vault) => vault.propertiesPaneLayout);
  const saving = useVaultSelector((vault) => vault.propertiesPaneLayoutSaving);
  const ready = useVaultSelector((vault) => vault.status === "ready");
  const error = useVaultSelector((vault) => vault.propertiesPaneLayoutError);
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 6 } }), useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }));
  const order = layout.order.filter((id) => !sections || sections[id] != null);
  const move = (id: PropertiesPaneSection, over: PropertiesPaneSection) => {
    if (id === over) return;
    void updatePropertiesPaneLayout({ ...layout, order: arrayMove(layout.order, layout.order.indexOf(id), layout.order.indexOf(over)) });
  };
  return <div className="flex shrink-0 flex-col bg-inherit">
    {error && <p role="alert" className="px-4 py-2 text-xs text-destructive">{error}</p>}
    <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={({ active, over }) => {
      if (over && order.includes(active.id as PropertiesPaneSection) && order.includes(over.id as PropertiesPaneSection)) move(active.id as PropertiesPaneSection, over.id as PropertiesPaneSection);
    }}>
      <SortableContext items={order} strategy={verticalListSortingStrategy}>
        {order.map((id, index) => <Section key={id} id={id} collapsed={layout.collapsed.includes(id)} disabled={saving || !ready}
          first={index === 0} last={index === order.length - 1} settings={!sections}
          onToggle={() => void updatePropertiesPaneLayout({ ...layout, collapsed: layout.collapsed.includes(id) ? layout.collapsed.filter((item) => item !== id) : [...layout.collapsed, id] })}
          onMove={(direction) => { const over = order[index + direction]; if (over) move(id, over); }}>
          {sections?.[id]}
        </Section>)}
      </SortableContext>
    </DndContext>
  </div>;
}

export function PropertiesPaneSettings() {
  const saving = useVaultSelector((vault) => vault.propertiesPaneLayoutSaving);
  return <section className="mb-5" aria-label="Properties pane layout">
    <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">Properties pane</h3>
    <p className="mb-3 text-xs text-muted-foreground">Drag sections or use their menus to reorder them. Click a heading to collapse or expand it. Saved for all notes in this vault.</p>
    <div className="overflow-hidden rounded-lg border border-border bg-zerus-surface"><PropertiesPaneSections /></div>
    <Button variant="ghost" size="sm" className="mt-2 text-xs" disabled={saving} onClick={() => void updatePropertiesPaneLayout(DEFAULT_PROPERTIES_PANE_LAYOUT)}>Reset pane layout</Button>
  </section>;
}
