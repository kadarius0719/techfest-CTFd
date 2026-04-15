import Alpine from "alpinejs";
import CTFd from "./index";
import "./secrets"; // Easter egg — check the source map

window.CTFd = CTFd;
window.Alpine = Alpine;

Alpine.start();
