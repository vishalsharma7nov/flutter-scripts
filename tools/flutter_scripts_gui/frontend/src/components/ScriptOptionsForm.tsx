import type { FormValues, ScriptField, ScriptFormDef } from '../scriptForms'
import { isFieldVisible } from '../scriptForms'

export type SelectOption = { value: string; label: string }

type Props = {
  def: ScriptFormDef
  values: FormValues
  extra: string
  dynamicOptions?: Record<string, SelectOption[]>
  onChange: (values: FormValues) => void
  onExtraChange: (extra: string) => void
  disabled?: boolean
}

function resolveOptions(
  field: ScriptField,
  dynamicOptions?: Record<string, SelectOption[]>,
): SelectOption[] {
  if (field.optionsSource && dynamicOptions?.[field.optionsSource]?.length) {
    return dynamicOptions[field.optionsSource]!
  }
  return field.options ?? []
}

function PlatformIcon({ platform }: { platform: 'android' | 'ios' }) {
  if (platform === 'android') {
    return (
      <svg
        className="platform-icon"
        viewBox="0 0 24 24"
        aria-hidden
        focusable="false"
      >
        <path
          fill="currentColor"
          d="M17.6 9.48l1.84-3.18c.16-.31.04-.69-.26-.85a.61.61 0 0 0-.83.22l-1.88 3.24a11.43 11.43 0 0 0-8.94 0L5.65 5.67a.61.61 0 0 0-.84-.22c-.3.16-.42.54-.26.85l1.84 3.18C2.92 11.03 1 14.22 1 17.75h22c0-3.53-1.92-6.72-5.4-8.27zM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5z"
        />
      </svg>
    )
  }
  return (
    <svg
      className="platform-icon"
      viewBox="0 0 24 24"
      aria-hidden
      focusable="false"
    >
      <path
        fill="currentColor"
        d="M16.365 1.43c0 1.14-.493 2.27-1.177 3.08-.744.9-1.99 1.57-2.987 1.57-.12 0-.23-.02-.3-.03-.01-.06-.04-.22-.04-.45 0-1.1.572-2.27 1.206-2.98.804-.94 2.142-1.64 3.248-1.68.03.13.06.28.06.44zm4.32 15.71c-.76.88-1.78 1.56-2.86 1.56-1.31 0-1.6-.87-3.05-.87-1.47 0-1.93.84-3.12.84-1.22 0-2.4-.68-3.2-1.74-1.38-1.96-2.45-5.52-1.02-7.94.72-1.24 2.01-2.04 3.4-2.06 1.32-.02 2.57.89 3.05.89.47 0 2.02-1.1 3.41-.94.58.02 2.22.24 3.27 1.79-.09.05-1.95 1.14-1.93 3.41.03 2.71 2.37 3.62 2.39 3.63-.02.06-.37 1.27-1.22 2.51z"
      />
    </svg>
  )
}

function PlatformPicker({
  field,
  value,
  onChange,
  disabled,
  options,
}: {
  field: ScriptField
  value: string
  onChange: (v: string) => void
  disabled?: boolean
  options: SelectOption[]
}) {
  return (
    <div className="form-field form-field-platform">
      <span className="form-label">
        {field.label}
        {field.required ? ' *' : ''}
      </span>
      <div className="platform-segment" role="radiogroup" aria-label={field.label}>
        {options.map((opt) => {
          const id = opt.value as 'android' | 'ios'
          const active = value === opt.value
          return (
            <button
              key={opt.value}
              type="button"
              role="radio"
              aria-checked={active}
              disabled={disabled}
              className={`platform-option platform-${id}${active ? ' active' : ''}`}
              onClick={() => onChange(opt.value)}
            >
              <PlatformIcon platform={id === 'ios' ? 'ios' : 'android'} />
              <span className="platform-option-label">{opt.label}</span>
            </button>
          )
        })}
      </div>
      {field.help ? <span className="form-help">{field.help}</span> : null}
    </div>
  )
}

function FieldControl({
  field,
  value,
  onChange,
  disabled,
  dynamicOptions,
}: {
  field: ScriptField
  value: string | boolean
  onChange: (v: string | boolean) => void
  disabled?: boolean
  dynamicOptions?: Record<string, SelectOption[]>
}) {
  if (field.type === 'checkbox') {
    return (
      <label className="form-check">
        <input
          type="checkbox"
          checked={value === true}
          disabled={disabled}
          onChange={(e) => onChange(e.target.checked)}
        />
        <span>{field.label}</span>
      </label>
    )
  }

  const options = resolveOptions(field, dynamicOptions)
  if (
    field.control === 'platform' &&
    (field.type === 'select' || field.type === 'positional') &&
    options.length
  ) {
    return (
      <PlatformPicker
        field={field}
        value={String(value ?? '')}
        disabled={disabled}
        options={options}
        onChange={(v) => onChange(v)}
      />
    )
  }

  if (
    (field.type === 'select' || field.type === 'positional') &&
    options.length
  ) {
    return (
      <label className="form-field">
        <span className="form-label">
          {field.label}
          {field.required ? ' *' : ''}
        </span>
        <select
          value={String(value ?? '')}
          disabled={disabled}
          onChange={(e) => onChange(e.target.value)}
        >
          {options.map((opt) => (
            <option key={opt.value || opt.label} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
        {field.help ? <span className="form-help">{field.help}</span> : null}
      </label>
    )
  }

  return (
    <label className="form-field">
      <span className="form-label">
        {field.label}
        {field.required ? ' *' : ''}
      </span>
      <input
        type="text"
        value={String(value ?? '')}
        placeholder={field.placeholder}
        disabled={disabled}
        onChange={(e) => onChange(e.target.value)}
      />
      {field.help ? <span className="form-help">{field.help}</span> : null}
    </label>
  )
}

export function ScriptOptionsForm({
  def,
  values,
  extra,
  dynamicOptions,
  onChange,
  onExtraChange,
  disabled,
}: Props) {
  const visibleFields = def.fields.filter((field) =>
    isFieldVisible(field, values),
  )

  return (
    <div className="script-form">
      {visibleFields.length > 0 ? (
        <div className="script-form-grid">
          {visibleFields.map((field) => (
            <FieldControl
              key={field.id}
              field={field}
              value={values[field.id] ?? (field.type === 'checkbox' ? false : '')}
              disabled={disabled}
              dynamicOptions={dynamicOptions}
              onChange={(v) => onChange({ ...values, [field.id]: v })}
            />
          ))}
        </div>
      ) : (
        <p className="form-help dim">No options — runs with defaults.</p>
      )}
      {(def.allowExtra !== false || def.fields.length === 0) && (
        <label className="form-field">
          <span className="form-label">Extra args</span>
          <input
            type="text"
            className="args"
            value={extra}
            placeholder="Optional extra CLI args…"
            disabled={disabled}
            onChange={(e) => onExtraChange(e.target.value)}
          />
        </label>
      )}
    </div>
  )
}
