import { useId, useRef, useState, type KeyboardEvent, type ReactNode } from 'react';

export type TabItem = {
  id: string;
  label: string;
  content: ReactNode;
};

export type TabsProps = {
  label: string;
  items: readonly TabItem[];
};

export function Tabs({ items, label }: TabsProps) {
  const baseId = useId().replaceAll(':', '');
  const [selectedId, setSelectedId] = useState(items[0]?.id ?? '');
  const tabRefs = useRef<Array<HTMLButtonElement | null>>([]);

  if (items.length === 0) {
    return null;
  }

  const selectedIndex = Math.max(
    0,
    items.findIndex((item) => item.id === selectedId),
  );

  const activateTab = (index: number) => {
    const item = items[index];

    if (!item) {
      return;
    }

    setSelectedId(item.id);
    tabRefs.current[index]?.focus();
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLButtonElement>, index: number) => {
    let nextIndex: number | undefined;

    switch (event.key) {
      case 'ArrowRight':
        nextIndex = (index + 1) % items.length;
        break;
      case 'ArrowLeft':
        nextIndex = (index - 1 + items.length) % items.length;
        break;
      case 'Home':
        nextIndex = 0;
        break;
      case 'End':
        nextIndex = items.length - 1;
        break;
      default:
        return;
    }

    event.preventDefault();
    activateTab(nextIndex);
  };

  return (
    <div className="ma-tabs">
      <div aria-label={label} className="ma-tabs__list" role="tablist">
        {items.map((item, index) => {
          const selected = index === selectedIndex;
          const tabId = `${baseId}-${item.id}-tab`;
          const panelId = `${baseId}-${item.id}-panel`;

          return (
            <button
              key={item.id}
              ref={(element) => {
                tabRefs.current[index] = element;
              }}
              aria-controls={panelId}
              aria-selected={selected}
              className="ma-tabs__tab"
              id={tabId}
              role="tab"
              tabIndex={selected ? 0 : -1}
              type="button"
              onClick={() => activateTab(index)}
              onKeyDown={(event) => handleKeyDown(event, index)}
            >
              {item.label}
            </button>
          );
        })}
      </div>

      {items.map((item, index) => {
        const selected = index === selectedIndex;
        const tabId = `${baseId}-${item.id}-tab`;
        const panelId = `${baseId}-${item.id}-panel`;

        return (
          <section
            key={item.id}
            aria-labelledby={tabId}
            className="ma-tabs__panel"
            hidden={!selected}
            id={panelId}
            role="tabpanel"
            tabIndex={0}
          >
            {item.content}
          </section>
        );
      })}
    </div>
  );
}
