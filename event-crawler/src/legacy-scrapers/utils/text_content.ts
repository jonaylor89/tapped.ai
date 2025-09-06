import type { Page } from "puppeteer";

export async function getTextContent(page: Page, selector: string) {
  const content = await page.evaluate((selector) => {
    function getAllTextContent(element: Element | ChildNode) {
      let text = "";

      try {
        // Iterate over child nodes
        element.childNodes.forEach((node) => {
          if (node.nodeType === Node.TEXT_NODE) {
            text += ` ${node.textContent} `;
          } else if (node.nodeType === Node.ELEMENT_NODE) {
            text += ` ${getAllTextContent(node)} `;
          }
        });
      } catch (error) {
        console.error("[-] error getting text content", error);
      }

      return text;
    }

    const containers = document.querySelectorAll(selector);

    if (containers.length === 0) {
      return "";
    }
    return Array.from(containers)
      .map((container) => {
        const blah = getAllTextContent(container).trim();
        return blah;
      })
      .join("");
  }, selector);

  return content;
}
