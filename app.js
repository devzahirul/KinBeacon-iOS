'use strict';
const screens = {
  "map": {
    "role": "parent",
    "title": "Family map",
    "file": "01-parent-map.png",
    "description": "See your family on one map, with safe places, battery levels and directions. Ask for a check-in when you want a little reassurance.",
    "alt": "Parent family map showing Emma at school and Lucas at home"
  },
  "profile": {
    "role": "parent",
    "title": "A closer look",
    "file": "02-parent-child-detail.png",
    "description": "Location, device status and safety information come together in your child’s profile. See the details that help you plan your day.",
    "alt": "Child profile showing location, device status and safety details"
  },
  "controls": {
    "role": "parent",
    "title": "Time to focus",
    "file": "03-parent-controls.png",
    "description": "School, Homework and Bedtime modes help create room for what matters. Choose allowed apps and set limits using Apple’s Screen Time.",
    "alt": "Parent controls with School Mode and app restrictions"
  },
  "schedule": {
    "role": "parent",
    "title": "A daily rhythm",
    "file": "04-parent-school-schedule.png",
    "description": "Set the hours and days for School Mode, then choose the apps your child can use. A routine you can adjust as family life changes.",
    "alt": "School Mode schedule editor with hours, weekdays and allowed apps"
  },
  "activity": {
    "role": "parent",
    "title": "The bigger picture",
    "file": "05-parent-activity.png",
    "description": "Explore daily, weekly and monthly screen-time summaries, a location timeline, and requests for a little extra time. Screen Time reports stay on the device.",
    "alt": "Parent activity screen with screen-time summaries and extra-time requests"
  },
  "alerts": {
    "role": "parent",
    "title": "Stay in the loop",
    "file": "06-parent-safety-alert.png",
    "description": "Know when location sharing or Screen Time access needs attention. Send guidance to the child’s device and see its reported status.",
    "alt": "Safety alert for location permissions with a fix-on-child-device action"
  },
  "home": {
    "role": "child",
    "title": "Their own home",
    "file": "07-child-home.png",
    "description": "A clear view of protection, location sharing, School Mode and connectivity. Request more time, check in, or reach the family from one place.",
    "alt": "Child companion showing protection, School Mode, check-in and SOS"
  },
  "request": {
    "role": "child",
    "title": "A little more time",
    "file": "08-child-request-time.png",
    "description": "Ask for 15, 30 or 60 extra minutes, with an optional message. Follow the request while a parent decides.",
    "alt": "Child request screen with extra-time choices and an optional message"
  },
  "checkin": {
    "role": "child",
    "title": "A quick “I’m OK”",
    "file": "09-child-check-in.png",
    "description": "Send “I’m OK,” “Picked up,” “On my way,” or “Need help.” Add a message so your family has the context they need.",
    "alt": "Child check-in options with a message field"
  },
  "shield": {
    "role": "child",
    "title": "A gentle boundary",
    "file": "10-child-shield.png",
    "description": "A clear explanation when an app is unavailable during a focus mode. Apple’s Screen Time applies the restrictions on the child’s device.",
    "alt": "App shield explaining that Instagram is unavailable during School Mode"
  },
  "childactivity": {
    "role": "child",
    "title": "Understand the day",
    "file": "11-child-activity.png",
    "description": "Give children a view of their own activity, with Screen Time reports processed on the device by Apple.",
    "alt": "Child activity screen with an on-device usage summary"
  },
  "help": {
    "role": "child",
    "title": "Help, made clear",
    "file": "12-child-help.png",
    "description": "Understand why permissions are needed and what to do when something needs attention. Location sharing stays visible to the child.",
    "alt": "Child help screen showing permission health and one-tap fixes"
  }
};
let role = 'parent';
let current = 'map';
const tablist = document.querySelector('.screen-tabs');
const gallery = document.getElementById('gallery-image');
const panel = document.getElementById('screen-panel');
const roleButtons = [...document.querySelectorAll('[data-role]')];
const dialog = document.getElementById('screenshot-dialog');
const roleKeys = () => Object.keys(screens).filter(key => screens[key].role === role);
function renderTabs() {
  tablist.replaceChildren();
  tablist.setAttribute('aria-label', `Explore ${role} app screens`);
  roleKeys().forEach((key, index) => {
    const tab = document.createElement('button');
    tab.type = 'button';
    tab.id = `tab-${key}`;
    tab.dataset.screen = key;
    tab.setAttribute('role', 'tab');
    tab.setAttribute('aria-controls', 'screen-panel');
    const number = document.createElement('span');
    number.className = 'tab-number';
    number.textContent = String(index + 1).padStart(2, '0');
    const title = document.createElement('span');
    title.textContent = screens[key].title;
    const plus = document.createElement('span');
    plus.className = 'tab-plus';
    plus.textContent = '+';
    plus.setAttribute('aria-hidden', 'true');
    tab.append(number, title, plus);
    tablist.append(tab);
  });
  roleButtons.forEach(button => {
    const selected = button.dataset.role === role;
    button.classList.toggle('active', selected);
    button.setAttribute('aria-pressed', String(selected));
  });
}
function selectScreen(key, focus = false) {
  if (!screens[key]) return;
  if (screens[key].role !== role) {
    role = screens[key].role;
    renderTabs();
  }
  current = key;
  tablist.querySelectorAll('[role="tab"]').forEach(tab => {
    const selected = tab.dataset.screen === key;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
    if (selected && focus) tab.focus();
  });
  const screen = screens[key];
  gallery.src = `./assets/${screen.file}`;
  gallery.alt = screen.alt;
  document.getElementById('screen-description').textContent = screen.description;
  document.getElementById('stage-caption').textContent = `${screen.title.toUpperCase()} / ${role.toUpperCase()}`;
  const keys = roleKeys();
  document.getElementById('stage-index').textContent = `${String(keys.indexOf(key) + 1).padStart(2, '0')} / ${String(keys.length).padStart(2, '0')}`;
  panel.setAttribute('aria-labelledby', `tab-${key}`);
  document.querySelector('.screen-zoom').setAttribute('aria-label', `Expand ${screen.title.toLowerCase()} screenshot`);
}
roleButtons.forEach(button => button.addEventListener('click', () => {
  if (role === button.dataset.role) return;
  role = button.dataset.role;
  renderTabs();
  selectScreen(roleKeys()[0]);
}));
tablist.addEventListener('click', event => {
  const tab = event.target.closest('[data-screen]');
  if (tab) selectScreen(tab.dataset.screen);
});
tablist.addEventListener('keydown', event => {
  if (!event.target.closest('[role="tab"]')) return;
  const keys = roleKeys();
  const index = keys.indexOf(current);
  let next;
  if (['ArrowDown', 'ArrowRight'].includes(event.key)) next = keys[(index + 1) % keys.length];
  if (['ArrowUp', 'ArrowLeft'].includes(event.key)) next = keys[(index - 1 + keys.length) % keys.length];
  if (event.key === 'Home') next = keys[0];
  if (event.key === 'End') next = keys[keys.length - 1];
  if (next) { event.preventDefault(); selectScreen(next, true); }
});
document.querySelectorAll('[data-show-screen]').forEach(link => link.addEventListener('click', () => selectScreen(link.dataset.showScreen)));
document.querySelector('.screen-zoom').addEventListener('click', () => {
  const fullImage = document.getElementById('dialog-image');
  fullImage.src = gallery.src;
  fullImage.alt = gallery.alt;
  document.getElementById('dialog-title').textContent = `KinBeacon · ${role === 'parent' ? 'Parent' : 'Child'} · ${screens[current].title}`;
  dialog.showModal();
  document.body.style.overflow = 'hidden';
});
document.querySelector('.dialog-close').addEventListener('click', () => dialog.close());
dialog.addEventListener('click', event => {
  if (event.target !== dialog) return;
  const rect = dialog.getBoundingClientRect();
  if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
});
dialog.addEventListener('close', () => { document.body.style.overflow = ''; });
selectScreen(current);
