import { useMemo, useState } from 'react'
import type { HowToTopic } from '../data/howToTopics'
import { howToCategories } from '../data/howToTopics'
import { normalizeCommands } from '../data/types'

type Props = {
  topics: HowToTopic[]
  selectedId: string | null
  onSelect: (id: string) => void
  search: string
  onSearchChange: (v: string) => void
}

function topicMatches(topic: HowToTopic, q: string): boolean {
  if (!q) return true
  const hay = [
    topic.title,
    topic.summary,
    topic.category,
    ...topic.steps.flatMap((s) => [
      s.title,
      s.note ?? '',
      ...normalizeCommands(s.commands).map((c) => c.cmd),
    ]),
  ]
    .join(' ')
    .toLowerCase()
  return hay.includes(q)
}

export function HowToList({
  topics,
  selectedId,
  onSelect,
  search,
  onSearchChange,
}: Props) {
  const q = search.trim().toLowerCase()
  const filtered = useMemo(
    () => topics.filter((t) => topicMatches(t, q)),
    [topics, q],
  )
  const categories = howToCategories(filtered)

  return (
    <div className="list-panel">
      <input
        className="git-search"
        placeholder="Search how-tos / commands…"
        value={search}
        onChange={(e) => onSearchChange(e.target.value)}
        aria-label="Search how-to topics"
      />
      {categories.length === 0 ? (
        <p className="hint">No how-tos match.</p>
      ) : (
        categories.map((category) => (
          <div key={category} className="list-group">
            <h3 className="list-group-title">{category}</h3>
            <ul>
              {filtered
                .filter((t) => t.category === category)
                .map((topic) => (
                  <li key={topic.id}>
                    <button
                      type="button"
                      className={
                        selectedId === topic.id
                          ? 'list-item active'
                          : 'list-item'
                      }
                      onClick={() => onSelect(topic.id)}
                    >
                      {topic.title}
                    </button>
                  </li>
                ))}
            </ul>
          </div>
        ))
      )}
    </div>
  )
}
