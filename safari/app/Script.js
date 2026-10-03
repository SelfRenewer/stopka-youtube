// Стопка: окно приложения-контейнера. Показывает, включено ли расширение.

function show(enabled) {
    if (typeof enabled === "boolean") {
        document.body.classList.toggle("state-on", enabled);
        document.body.classList.toggle("state-off", !enabled);
    } else {
        document.body.classList.remove("state-on", "state-off");
    }
}

function send(message) {
    webkit.messageHandlers.controller.postMessage(message);
}

document.querySelector("button.open-preferences").addEventListener("click", () => send("open-preferences"));
document.querySelector("button.privacy").addEventListener("click", () => send("open-privacy"));
