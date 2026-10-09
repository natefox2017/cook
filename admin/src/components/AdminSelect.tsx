import * as Select from "@radix-ui/react-select";
import { Check, ChevronDown } from "lucide-react";
import "./AdminSelect.css";

export type AdminSelectOption = { value: string; label: string };

type AdminSelectProps = {
  label: string;
  value: string;
  options: AdminSelectOption[];
  onValueChange: (value: string) => void;
  className?: string;
  triggerClassName?: string;
};

export function AdminSelect({
  label,
  value,
  options,
  onValueChange,
  className = "",
  triggerClassName = "",
}: AdminSelectProps) {
  return (
    <div className={`admin-select-field ${className}`.trim()}>
      <span className="admin-select-label">{label}</span>
      <Select.Root value={value} onValueChange={onValueChange}>
        <Select.Trigger aria-label={label} className={`admin-select-trigger ${triggerClassName}`.trim()}>
          <Select.Value />
          <Select.Icon asChild><ChevronDown size={15} aria-hidden="true" /></Select.Icon>
        </Select.Trigger>
        <Select.Portal>
          <Select.Content className="admin-select-content" position="popper" sideOffset={4}>
            <Select.Viewport className="admin-select-viewport">
              {options.map((option) => (
                <Select.Item className="admin-select-item" key={option.value} value={option.value}>
                  <Select.ItemText>{option.label}</Select.ItemText>
                  <Select.ItemIndicator asChild><Check size={14} aria-hidden="true" /></Select.ItemIndicator>
                </Select.Item>
              ))}
            </Select.Viewport>
          </Select.Content>
        </Select.Portal>
      </Select.Root>
    </div>
  );
}
