const trigger = document.querySelector("#trigger");
const targets = [...document.querySelectorAll(".target")];
const wires = [...document.querySelectorAll(".wires path")];
const status = document.querySelector("#demo-status");
const reset = document.querySelector("#reset-demo");
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
let count = 0;
let running = false;
trigger.disabled = false;
const pause = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));
trigger.addEventListener("click", async () => {
  if (running) return;
  running = true;
  trigger.setAttribute("aria-disabled", "true");
  reset.setAttribute("aria-disabled", "true");
  count += 1;
  for (let index = 0; index < targets.length; index += 1) {
    targets[index].classList.add("active");
    wires[index].classList.add("active");
    targets[index].querySelector(".count").textContent = count;
    if (!reducedMotion.matches) await pause(180);
    targets[index].classList.remove("active");
    wires[index].classList.remove("active");
  }
  status.textContent = `All four buttons clicked. Each counter is now ${count}.`;
  reset.hidden = false;
  running = false;
  trigger.removeAttribute("aria-disabled");
  reset.removeAttribute("aria-disabled");
});
reset.addEventListener("click", () => {
  if (running) return;
  count = 0;
  targets.forEach((target) => {
    target.querySelector(".count").textContent = "0";
  });
  status.textContent = "All four counters reset to zero.";
  // Keep focus on the reset button after keyboard activation.
});
const copy = document.querySelector("#copy-command");
copy.hidden = false;
copy.addEventListener("click", async () => {
  const command = document.querySelector(".brew code").textContent;
  const copyStatus = document.querySelector("#copy-status");
  try {
    await navigator.clipboard.writeText(command);
    copyStatus.textContent = "Copied. Paste into Terminal to install.";
  } catch {
    copyStatus.textContent = "Select and copy the command above.";
  }
});
