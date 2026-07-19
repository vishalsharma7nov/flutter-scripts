import type { HowToTopic } from '../data/howToTopics';
import { StepsList } from './CommandBlock';

type Props = {
  topic: HowToTopic;
};

export function HowToDetail({ topic }: Props) {
  return (
    <article className="detail-panel">
      <header>
        <p className="eyebrow">{topic.category}</p>
        <h2>{topic.title}</h2>
        <p className="summary">{topic.summary}</p>
      </header>
      <StepsList steps={topic.steps} />
    </article>
  );
}
