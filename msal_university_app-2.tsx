import React, { useState, useEffect } from 'react';

// Фирменные цвета вынесены в CSS-переменные для поддержки тёмной темы
const COLORS = {
  primary: 'var(--color-primary)',
  secondary: 'var(--color-secondary)',
  accent: 'var(--color-accent)',
  dark: 'var(--color-dark)',
  bg: 'var(--color-bg)',
  card: 'var(--color-card)',
  border: 'var(--color-border)',
  textMuted: 'var(--color-text-muted)'
};

// Набор легковесных SVG-иконок для независимости от внешних библиотек
const Icons = {
  Home: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
  ),
  Calendar: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
  ),
  GraduationCap: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M22 10v6M2 10l10-5 10 5-10 5z"/><path d="M6 12v5c3 3 9 3 12 0v-5"/></svg>
  ),
  Mail: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></svg>
  ),
  Settings: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/></svg>
  ),
  Bell: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/></svg>
  ),
  Search: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>
  ),
  User: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
  ),
  Map: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="3 6 9 3 15 6 21 3 21 18 15 21 9 18 3 21"/><line x1="9" x2="9" y1="3" y2="18"/><line x1="15" x2="15" y1="6" y2="21"/></svg>
  ),
  LogOut: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/></svg>
  ),
  ArrowLeft: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m12 19-7-7 7-7"/><path d="M19 12H5"/></svg>
  ),
  Smartphone: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect width="14" height="20" x="5" y="2" rx="2" ry="2"/><path d="M12 18h.01"/></svg>
  ),
  Monitor: ({ size = 24, color = "currentColor" }) => (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect width="20" height="14" x="2" y="3" rx="2"/><line x1="8" x2="16" y1="21" y2="21"/><line x1="12" x2="12" y1="17" y2="21"/></svg>
  )
};

const MOCK_USER = {
  name: "Елена Волкова",
  faculty: "Юридический Факультет",
  course: "3 курс, Гр. 302",
  gpa: "4.8",
  debts: 0,
  avatar: "https://placehold.co/100x100/6aaab0/ffffff?text=ЕВ"
};

const MOCK_SCHEDULE = [
  { id: 1, time: "09:45 - 11:15", subject: "Конституционное право", type: "Лекция", room: "Ауд. 402", teacher: "Проф. Иванова С.А.", isNext: true, avgGrade: "4.8", admission: true },
  { id: 2, time: "11:30 - 13:00", subject: "Гражданское право", type: "Семинар", room: "Ауд. 315", teacher: "Доц. Петров В.И.", isNext: false, avgGrade: "4.2", admission: true },
  { id: 3, time: "14:00 - 15:30", subject: "Академическое письмо", type: "Практика", room: "Ауд. 101", teacher: "Смирнова А.В.", isNext: false, avgGrade: "4.9", admission: false }
];

const MOCK_GRADES = [
  { id: 1, subject: "Гражданское право", type: "Экзамен", grade: 5, date: "15.01.2024", teacher: "Проф. Иванов" },
  { id: 2, subject: "Уголовный процесс", type: "Экзамен", grade: 4, date: "18.01.2024", teacher: "Проф. Сидоров" },
  { id: 3, subject: "Административное право", type: "Зачёт", grade: "Зачтено", date: "22.01.2024", teacher: "Доц. Петрова" },
  { id: 4, subject: "Логика", type: "Зачёт", grade: "Зачтено", date: "25.01.2024", teacher: "Кузнецов А.А." }
];

const MOCK_EMAILS = [
  { id: 1, sender: "Проф. Иванова", subject: "Материалы к семинару", preview: "Здравствуйте! Направляю вам список литературы...", time: "09:12", unread: true, avatarBg: "#1f5a56" },
  { id: 2, sender: "Учебный отдел", subject: "Изменения в расписании", preview: "Внимание! Завтрашняя лекция переносится...", time: "08:30", unread: true, avatarBg: "#036495" },
  { id: 3, sender: "Библиотека МГЮА", subject: "Срок сдачи книг", preview: "Напоминаем, что вам необходимо сдать...", time: "Вчера", unread: false, avatarBg: "#6aaab0" },
  { id: 4, sender: "Студсовет", subject: "Выборы председателя", preview: "Приглашаем всех студентов принять участие...", time: "Вчера", unread: false, avatarBg: "#3b362e" },
];

const Card = ({ children, className = "", onClick }) => (
  <div onClick={onClick} className={`rounded-2xl shadow-sm p-4 transition-colors ${className}`} style={{ backgroundColor: COLORS.card, borderColor: COLORS.border, borderWidth: 1 }}>
    {children}
  </div>
);

const Badge = ({ children, type = "primary" }) => {
  let bg = COLORS.primary;
  let text = '#fff';
  let border = 'transparent';
  if (type === 'accent') { bg = COLORS.accent; }
  else if (type === 'outline') { bg = 'transparent'; border = COLORS.accent; text = COLORS.primary; }
  else if (type === 'dark') { bg = COLORS.dark; text = COLORS.bg; }
  
  return (
    <span className="px-2.5 py-1 text-xs font-semibold rounded-full" style={{ backgroundColor: bg, color: text, borderColor: border, borderWidth: type === 'outline' ? 1 : 0 }}>
      {children}
    </span>
  );
};

const LoginScreen = ({ onLogin }) => {
  return (
    <div className="min-h-screen flex items-center justify-center p-4 transition-colors" style={{ backgroundColor: COLORS.bg }}>
      <div className="max-w-md w-full">
        {/* Логотип */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-24 h-24 rounded-full mb-4 shadow-lg" style={{ backgroundColor: COLORS.primary }}>
             <Icons.GraduationCap size={48} color="white" />
          </div>
          <h1 className="text-2xl font-bold" style={{ color: COLORS.primary }}>Университет</h1>
          <p className="text-sm uppercase tracking-widest font-semibold mt-1" style={{ color: COLORS.secondary }}>Личный кабинет</p>
        </div>

        {/* Форма */}
        <Card className="p-6">
          <h2 className="text-xl font-bold mb-6 text-center" style={{ color: COLORS.dark }}>Вход в систему</h2>
          
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium mb-1" style={{ color: COLORS.dark }}>E-mail или Логин</label>
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                  <Icons.User size={18} color={COLORS.accent} />
                </div>
                <input 
                  type="text" 
                  placeholder="Введите ваш email или логин" 
                  className="pl-10 w-full p-3 rounded-xl focus:ring-2 focus:outline-none transition-all"
                  style={{ backgroundColor: COLORS.bg, borderColor: COLORS.border, borderWidth: 1, color: COLORS.dark }}
                  defaultValue="student@msal.ru"
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium mb-1" style={{ color: COLORS.dark }}>Пароль</label>
              <div className="relative">
                <input 
                  type="password" 
                  placeholder="Введите ваш пароль" 
                  className="w-full p-3 rounded-xl focus:ring-2 focus:outline-none transition-all"
                  style={{ backgroundColor: COLORS.bg, borderColor: COLORS.border, borderWidth: 1, color: COLORS.dark }}
                  defaultValue="password123"
                />
              </div>
            </div>

            <div className="flex items-center justify-between text-sm">
              <label className="flex items-center space-x-2 cursor-pointer">
                <input type="checkbox" className="rounded focus:ring-blue-500" defaultChecked />
                <span style={{ color: COLORS.dark }}>Запомнить меня</span>
            </label>
            <button style={{ color: COLORS.secondary }} className="font-semibold hover:underline">Забыли пароль?</button>
          </div>

            <button 
              onClick={onLogin}
              className="w-full py-3.5 rounded-xl text-white font-bold text-lg shadow-md hover:opacity-90 transition-opacity mt-4"
              style={{ backgroundColor: COLORS.accent }}
            >
              ВОЙТИ
            </button>
          </div>
        </Card>
      </div>
    </div>
  );
};

const DashboardScreen = ({ navigate, viewMode }) => {
  // Скрываем блок быстрых действий, если активен десктопный вид (сайдбар видимый)
  const quickActionsClasses = viewMode === 'desktop' ? 'hidden' : (viewMode === 'mobile' ? 'block' : 'block md:hidden');

  return (
    <div className="space-y-6 pb-6 animate-in fade-in duration-300">
      {/* Профиль & Приветствие */}
      <div className="flex items-center justify-between">
        <div className="flex items-center space-x-4">
          <img src={MOCK_USER.avatar} alt="Avatar" className="w-14 h-14 rounded-full shadow-sm border-2" style={{ borderColor: COLORS.accent }} />
          <div>
            <p className="text-sm" style={{ color: COLORS.textMuted }}>Доброе утро,</p>
            <h2 className="text-lg font-bold" style={{ color: COLORS.dark }}>{MOCK_USER.name} 👋</h2>
          </div>
        </div>
        <button className="p-2 rounded-full shadow-sm relative" style={{ backgroundColor: COLORS.card, color: COLORS.dark }}>
          <Icons.Bell size={20} />
          <span className="absolute top-1 right-1 w-2.5 h-2.5 bg-red-500 rounded-full border-2" style={{ borderColor: COLORS.card }}></span>
        </button>
      </div>

      {/* Быстрые действия */}
      <div className={quickActionsClasses}>
        <h3 className="text-xs font-bold uppercase tracking-wider mb-3" style={{ color: COLORS.textMuted }}>Быстрые действия</h3>
        <div className="flex justify-between md:justify-start md:space-x-8">
          {[
            { icon: Icons.Calendar, label: "Расписание", path: "schedule" },
            { icon: Icons.GraduationCap, label: "Оценки", path: "grades" },
            { icon: Icons.User, label: "MyPrepod", path: "teachers" },
            { icon: Icons.Mail, label: "Почта", path: "mail" }
          ].map((action, idx) => (
            <div key={idx} className="flex flex-col items-center cursor-pointer" onClick={() => navigate(action.path)}>
              <div className="w-12 h-12 rounded-full flex items-center justify-center mb-1 text-white shadow-md hover:scale-105 transition-transform" style={{ backgroundColor: COLORS.secondary }}>
                <action.icon size={22} />
              </div>
              <span className="text-xs font-medium text-center leading-tight mt-1" style={{ color: COLORS.dark }}>{action.label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Ближайшая пара */}
      <div>
        <div className="flex justify-between items-center mb-3">
          <h3 className="text-xs font-bold uppercase tracking-wider" style={{ color: COLORS.textMuted }}>Пары сегодня</h3>
          <button className="text-xs font-semibold" style={{ color: COLORS.secondary }} onClick={() => navigate("schedule")}>Все</button>
        </div>
        <Card className="p-0 overflow-hidden divide-y" style={{ borderColor: COLORS.border }}>
          {MOCK_SCHEDULE.map((item, idx) => (
            <div key={item.id} className="p-4" style={item.isNext ? { backgroundColor: COLORS.primary } : { borderColor: COLORS.border }}>
              {item.isNext && <div className="text-xs font-semibold opacity-80 mb-1 flex justify-between text-white">
                <span>СЛЕДУЮЩАЯ ПАРА</span>
                <span>{item.time}</span>
              </div>}
              {!item.isNext && <div className="text-xs font-semibold mb-1" style={{ color: COLORS.textMuted }}>{item.time}</div>}
              
              <h4 className={`text-base font-bold ${item.isNext ? 'text-white' : ''}`} style={!item.isNext ? { color: COLORS.dark } : {}}>{item.subject} | {item.type}</h4>
              <p className={`text-sm mt-1 ${item.isNext ? 'text-gray-200' : ''}`} style={!item.isNext ? { color: COLORS.textMuted } : {}}>{item.room} | {item.teacher}</p>
            </div>
          ))}
        </Card>
      </div>

      {/* Непрочитанные сообщения */}
      <div>
        <h3 className="text-xs font-bold uppercase tracking-wider mb-3" style={{ color: COLORS.textMuted }}>Новые сообщения</h3>
        <Card className="space-y-4">
          {MOCK_EMAILS.filter(e => e.unread).map(email => (
            <div key={email.id} className="flex items-start space-x-3 cursor-pointer" onClick={() => navigate("mail")}>
              <div className="w-10 h-10 rounded-full flex items-center justify-center text-white font-bold text-sm shrink-0" style={{ backgroundColor: email.avatarBg }}>
                {email.sender.charAt(0)}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex justify-between">
                  <p className="text-sm font-bold truncate" style={{ color: COLORS.dark }}>{email.sender}</p>
                  <span className="text-xs font-semibold" style={{ color: COLORS.secondary }}>{email.time}</span>
                </div>
                <p className="text-sm font-medium truncate" style={{ color: COLORS.primary }}>{email.subject}</p>
                <p className="text-xs truncate" style={{ color: COLORS.textMuted }}>{email.preview}</p>
              </div>
            </div>
          ))}
        </Card>
      </div>
    </div>
  );
};

const ScheduleScreen = () => {
  return (
    <div className="animate-in fade-in duration-300 h-full flex flex-col">
      {/* Шапка расписания */}
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-bold" style={{ color: COLORS.primary }}>Расписание</h2>
        <div className="p-1 rounded-lg flex text-sm font-medium" style={{ backgroundColor: COLORS.border }}>
          <button className="px-3 py-1 rounded-md shadow-sm" style={{ backgroundColor: COLORS.card, color: COLORS.dark }}>День</button>
          <button className="px-3 py-1 rounded-md" style={{ color: COLORS.textMuted }}>Неделя</button>
        </div>
      </div>

      {/* Навигация по неделям */}
      <div className="flex justify-between items-center mb-4 px-1">
        <button className="p-2 rounded-full hover:bg-black/5 transition-colors" style={{ color: COLORS.dark }}>
          <Icons.ArrowLeft size={20} />
        </button>
        <span className="text-sm font-bold uppercase tracking-wider" style={{ color: COLORS.textMuted }}>14 - 20 Октября</span>
        <button className="p-2 rounded-full hover:bg-black/5 transition-colors" style={{ color: COLORS.dark, transform: 'rotate(180deg)' }}>
          <Icons.ArrowLeft size={20} />
        </button>
      </div>

      {/* Календарная лента */}
      <div className="flex justify-between items-center mb-6 px-1">
        {[14, 15, 16, 17, 18, 19].map((day, idx) => {
          const isToday = day === 15;
          const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
          return (
            <div key={day} className={`flex flex-col items-center justify-center w-12 h-14 rounded-xl ${isToday ? 'text-white' : ''}`} style={isToday ? { backgroundColor: COLORS.accent } : { color: COLORS.textMuted }}>
              <span className="text-xs mb-1">{days[idx]}</span>
              <span className={`text-lg font-bold ${isToday ? '' : ''}`} style={!isToday ? { color: COLORS.dark } : {}}>{day}</span>
            </div>
          );
        })}
      </div>

      <h3 className="text-sm font-bold uppercase tracking-wider mb-3" style={{ color: COLORS.textMuted }}>15 ОКТЯБРЯ, ВТОРНИК</h3>
      
      {/* Список пар */}
      <div className="space-y-4 flex-1 pb-20">
        {MOCK_SCHEDULE.map((item, idx) => (
          <div key={idx} className="relative pl-4">
            {/* Вертикальная линия (Timeline) */}
            <div className="absolute left-0 top-0 bottom-0 w-1 rounded-full" style={{ backgroundColor: item.isNext ? COLORS.accent : COLORS.primary, opacity: item.isNext ? 1 : 0.3 }}></div>
            
            <Card className="p-4" style={item.isNext ? { borderColor: COLORS.accent, borderWidth: '2px' } : {}}>
              <div className="flex justify-between mb-1">
                <span className="text-sm font-bold" style={{ color: COLORS.secondary }}>{item.time}</span>
                {item.isNext && <Badge type="accent">Идёт сейчас</Badge>}
              </div>
              <h4 className="text-lg font-bold mt-1 mb-1" style={{ color: COLORS.dark }}>{item.subject}</h4>
              <div className="text-sm space-y-1" style={{ color: COLORS.textMuted }}>
                <p>{item.type} • {item.room}</p>
                <div className="flex items-center mt-2">
                  <Icons.User size={14} className="mr-1 opacity-70" />
                  <span>{item.teacher}</span>
                </div>
                
                {/* Доп. информация: Допуск и Средний балл */}
                <div className="flex items-center justify-between mt-4 pt-3 border-t" style={{ borderColor: COLORS.border }}>
                  <div className="text-xs font-semibold px-2 py-1 rounded-md" style={{ backgroundColor: item.admission ? 'rgba(34, 197, 94, 0.1)' : 'rgba(239, 68, 68, 0.1)', color: item.admission ? '#16a34a' : '#dc2626' }}>
                    {item.admission ? 'Допуск получен' : 'Нет допуска'}
                  </div>
                  <div className="text-xs font-medium" style={{ color: COLORS.textMuted }}>
                    Ср. балл: <span className="font-bold text-sm" style={{ color: COLORS.dark }}>{item.avgGrade}</span>
                  </div>
                </div>
              </div>
            </Card>
          </div>
        ))}
      </div>
    </div>
  );
};

const GradesScreen = () => {
  return (
    <div className="animate-in fade-in duration-300 pb-6">
      <h2 className="text-xl font-bold mb-4" style={{ color: COLORS.primary }}>Успеваемость</h2>
      
      {/* Селектор семестра */}
      <div className="mb-6 relative">
        <button className="w-full p-4 rounded-2xl font-bold flex justify-between items-center shadow-sm transition-transform hover:scale-[1.01]" style={{ backgroundColor: COLORS.card, color: COLORS.dark, borderColor: COLORS.border, borderWidth: 1 }}>
          <div className="flex flex-col items-start">
             <span className="text-xs uppercase tracking-wider mb-1 font-semibold" style={{ color: COLORS.textMuted }}>Семестр</span>
             <span className="text-base">1 семестр 2023/24 (Текущий)</span>
          </div>
          <div className="w-8 h-8 rounded-full flex items-center justify-center" style={{ backgroundColor: COLORS.bg }}>
             <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={COLORS.secondary} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="m6 9 6 6 6-6"/></svg>
          </div>
        </button>
      </div>

      {/* Статистика */}
      <div className="grid grid-cols-2 gap-4 mb-6">
        <Card className="flex flex-col justify-center">
          <div className="flex items-center text-sm mb-1" style={{ color: COLORS.textMuted }}>
            <Icons.GraduationCap size={16} className="mr-1" /> Ср. балл
          </div>
          <div className="text-2xl font-bold" style={{ color: COLORS.secondary }}>{MOCK_USER.gpa}</div>
        </Card>
        <Card className="flex flex-col justify-center">
          <div className="flex items-center text-sm mb-1" style={{ color: COLORS.textMuted }}>
             Задолженности
          </div>
          <div className="text-2xl font-bold text-green-600">{MOCK_USER.debts}</div>
        </Card>
      </div>

      <h3 className="text-sm font-bold uppercase tracking-wider mb-3" style={{ color: COLORS.textMuted }}>Результаты сессии</h3>
      
      {/* Список предметов */}
      <div className="space-y-3">
        {MOCK_GRADES.map(grade => (
          <Card key={grade.id} className="p-4">
            <div className="flex justify-between items-start mb-2">
              <h4 className="font-bold text-base w-3/4" style={{ color: COLORS.dark }}>{grade.subject}</h4>
              <Badge type={grade.grade === 5 || grade.grade === "Зачтено" ? "primary" : "outline"}>
                {grade.grade}
              </Badge>
            </div>
            <div className="text-sm flex flex-wrap gap-x-3 gap-y-1 mt-2" style={{ color: COLORS.textMuted }}>
              <span>{grade.type}</span>
              <span>•</span>
              <span>{grade.date}</span>
              <span className="w-full text-xs mt-1">Преп: {grade.teacher}</span>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
};

const MailScreen = () => {
  const [selectedEmail, setSelectedEmail] = useState(null);

  // Режим просмотра письма
  if (selectedEmail) {
    return (
      <div className="animate-in slide-in-from-right-8 duration-300 h-full flex flex-col pb-6">
        <div className="flex items-center mb-6 space-x-4">
          <button onClick={() => setSelectedEmail(null)} className="p-2 rounded-full transition-colors" style={{ color: COLORS.dark, backgroundColor: COLORS.border }}>
            <Icons.ArrowLeft size={24} />
          </button>
          <h2 className="text-xl font-bold truncate" style={{ color: COLORS.primary }}>{selectedEmail.subject}</h2>
        </div>
        
        <Card className="p-5 flex-1 mb-4">
           <div className="flex justify-between items-start border-b pb-4 mb-4" style={{ borderColor: COLORS.border }}>
             <div className="flex items-center space-x-3">
               <div className="w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-lg" style={{ backgroundColor: selectedEmail.avatarBg }}>
                 {selectedEmail.sender.charAt(0)}
               </div>
               <div>
                 <h3 className="font-bold text-base" style={{ color: COLORS.dark }}>{selectedEmail.sender}</h3>
                 <p className="text-sm" style={{ color: COLORS.textMuted }}>Кому: мне</p>
               </div>
             </div>
             <span className="text-sm font-medium" style={{ color: COLORS.textMuted }}>{selectedEmail.time}</span>
           </div>
           <div className="text-base leading-relaxed space-y-4" style={{ color: COLORS.dark }}>
              <p>{selectedEmail.preview}</p>
              <p>Здравствуйте!</p>
              <p>Это полная версия письма. В реальном приложении здесь будет отображаться HTML-содержимое, загруженное с сервера, включая прикрепленные файлы и форматирование.</p>
              <p>С уважением,<br/>Команда МГЮА</p>
           </div>
        </Card>
      </div>
    );
  }

  // Режим списка писем
  return (
    <div className="animate-in fade-in duration-300 h-full flex flex-col pb-6">
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-bold" style={{ color: COLORS.primary }}>Почта</h2>
        <button className="p-2 rounded-full shadow-sm" style={{ backgroundColor: COLORS.card }}>
          <Icons.Search size={20} style={{ color: COLORS.dark }} />
        </button>
      </div>

      {/* Папки */}
      <div className="flex space-x-2 overflow-x-auto pb-2 mb-4 scrollbar-hide text-sm">
        <button className="px-4 py-2 rounded-full text-white whitespace-nowrap shadow-sm" style={{ backgroundColor: COLORS.accent }}>Входящие (2)</button>
        <button className="px-4 py-2 rounded-full whitespace-nowrap shadow-sm" style={{ backgroundColor: COLORS.card, color: COLORS.textMuted }}>Отправленные</button>
        <button className="px-4 py-2 rounded-full whitespace-nowrap shadow-sm" style={{ backgroundColor: COLORS.card, color: COLORS.textMuted }}>Черновики</button>
      </div>

      {/* Список писем */}
      <div className="space-y-3">
        {MOCK_EMAILS.map(email => (
          <Card key={email.id} onClick={() => setSelectedEmail(email)} className="p-4 cursor-pointer hover:scale-[1.01] transition-transform">
            <div className="flex items-start space-x-3">
              <div className="w-12 h-12 rounded-full flex items-center justify-center text-white font-bold text-lg shrink-0 shadow-inner" style={{ backgroundColor: email.avatarBg }}>
                {email.sender.charAt(0)}
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex justify-between items-center mb-0.5">
                  <h4 className={`text-base truncate ${email.unread ? 'font-bold' : 'font-semibold'}`} style={{ color: COLORS.dark }}>{email.sender}</h4>
                  <div className="flex items-center space-x-2">
                    <span className={`text-xs ${email.unread ? 'font-bold' : ''}`} style={{ color: email.unread ? COLORS.secondary : COLORS.textMuted }}>{email.time}</span>
                    {email.unread && <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: COLORS.secondary }}></span>}
                  </div>
                </div>
                <p className={`text-sm truncate mb-1 ${email.unread ? 'font-semibold' : ''}`} style={{ color: COLORS.primary }}>{email.subject}</p>
                <p className="text-sm truncate" style={{ color: COLORS.textMuted }}>{email.preview}</p>
              </div>
            </div>
          </Card>
        ))}
      </div>
      
      {/* FAB Написать письмо */}
      <button className="fixed bottom-24 right-6 w-14 h-14 rounded-full flex items-center justify-center text-white shadow-xl hover:scale-105 transition-transform md:absolute md:bottom-6 md:right-6" style={{ backgroundColor: COLORS.secondary }}>
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 5v14M5 12h14"/></svg>
      </button>
    </div>
  );
};

const SettingsScreen = ({ onLogout, isDark, toggleTheme }) => {
  return (
    <div className="animate-in fade-in duration-300 pb-10">
      <h2 className="text-xl font-bold mb-6" style={{ color: COLORS.primary }}>Настройки</h2>
      
      {/* Профиль карточка */}
      <Card className="p-4 mb-6 flex items-center space-x-4">
        <img src={MOCK_USER.avatar} alt="Profile" className="w-16 h-16 rounded-full border-2" style={{ borderColor: COLORS.accent }} />
        <div>
          <h3 className="text-lg font-bold" style={{ color: COLORS.dark }}>{MOCK_USER.name}</h3>
          <p className="text-sm" style={{ color: COLORS.textMuted }}>{MOCK_USER.faculty}</p>
          <p className="text-sm" style={{ color: COLORS.textMuted }}>{MOCK_USER.course}</p>
        </div>
      </Card>

      <div className="space-y-6">
        {/* Уведомления */}
        <section>
          <h4 className="text-xs font-bold uppercase tracking-wider mb-3 px-2" style={{ color: COLORS.accent }}>Уведомления</h4>
          <Card className="p-0 overflow-hidden divide-y" style={{ borderColor: COLORS.border }}>
            {[
              { label: "Push-уведомления", on: true },
              { label: "Изменения в расписании", on: true },
              { label: "Новые оценки", on: true },
              { label: "Почта", on: false }
            ].map((item, idx) => (
              <div key={idx} className="flex justify-between items-center p-4">
                <span className="font-medium" style={{ color: COLORS.dark }}>{item.label}</span>
                {/* Custom Toggle Switch */}
                <div className={`w-11 h-6 rounded-full relative cursor-pointer transition-colors ${item.on ? '' : 'bg-gray-400'}`} style={item.on ? { backgroundColor: COLORS.secondary } : {}}>
                  <div className={`absolute top-1 w-4 h-4 rounded-full bg-white transition-transform ${item.on ? 'left-6' : 'left-1'}`}></div>
                </div>
              </div>
            ))}
          </Card>
        </section>

        {/* Внешний вид */}
        <section>
          <h4 className="text-xs font-bold uppercase tracking-wider mb-3 px-2" style={{ color: COLORS.accent }}>Внешний вид</h4>
          <Card className="p-0 overflow-hidden divide-y" style={{ borderColor: COLORS.border }}>
             <div className="flex justify-between items-center p-4 cursor-pointer" onClick={toggleTheme}>
                <span className="font-medium" style={{ color: COLORS.dark }}>Тёмная тема</span>
                {/* Dark Mode Toggle Switch */}
                <div className={`w-11 h-6 rounded-full relative transition-colors ${isDark ? '' : 'bg-gray-400'}`} style={isDark ? { backgroundColor: COLORS.secondary } : {}}>
                  <div className={`absolute top-1 w-4 h-4 rounded-full bg-white transition-transform ${isDark ? 'left-6' : 'left-1'}`}></div>
                </div>
             </div>
          </Card>
        </section>

        {/* Выход */}
        <button onClick={onLogout} className="w-full flex justify-center items-center p-4 rounded-2xl shadow-sm font-bold transition-colors" style={{ backgroundColor: COLORS.card, color: '#ef4444', borderColor: COLORS.border, borderWidth: 1 }}>
          <Icons.LogOut size={20} className="mr-2" />
          ВЫЙТИ ИЗ АККАУНТА
        </button>
      </div>
    </div>
  );
};

const AppShell = ({ activeTab, setActiveTab, onLogout, isDark, toggleTheme, viewMode }) => {
  // Навигационное меню (используется и для Bottom Bar, и для Sidebar)
  const NAV_ITEMS = [
    { id: 'home', icon: Icons.Home, label: 'Главная' },
    { id: 'schedule', icon: Icons.Calendar, label: 'Расписание' },
    { id: 'grades', icon: Icons.GraduationCap, label: 'Оценки' },
    { id: 'mail', icon: Icons.Mail, label: 'Почта' },
    { id: 'settings', icon: Icons.Settings, label: 'Профиль' }
  ];

  const isMobileView = viewMode === 'mobile';
  const isDesktopView = viewMode === 'desktop';
  
  // Управляем классами в зависимости от режима (авто/симуляция)
  const sidebarClasses = isMobileView ? 'hidden' : (isDesktopView ? 'flex flex-col' : 'hidden md:flex flex-col');
  const bottomNavClasses = isDesktopView ? 'hidden' : (isMobileView ? 'flex' : 'md:hidden flex');

  const appContent = (
    <div className="flex h-screen w-full font-sans overflow-hidden transition-colors duration-300" style={{ backgroundColor: COLORS.bg }}>
      
      {/* САЙДБАР (Desktop / macOS & Tablet View) */}
      <aside className={`${sidebarClasses} w-64 h-full shadow-lg z-20 transition-colors duration-300 shrink-0`} style={{ backgroundColor: COLORS.primary }}>
        <div className="p-6 pt-10 flex items-center space-x-3">
          <div className="p-1.5 rounded-lg shadow-sm shrink-0" style={{ backgroundColor: COLORS.card }}>
             <Icons.GraduationCap size={28} color={COLORS.primary} />
          </div>
          <div>
            <h1 className="text-white font-bold text-lg leading-tight">МГЮА</h1>
            <p className="text-[10px] opacity-70 text-white font-medium mt-1 leading-tight">dark MSAL<br/>с любовью для альма матер</p>
          </div>
        </div>

        <nav className="flex-1 px-4 py-6 space-y-2">
          {NAV_ITEMS.map(item => (
            <button
              key={item.id}
              onClick={() => setActiveTab(item.id)}
              className={`w-full flex items-center space-x-3 px-4 py-3 rounded-xl transition-all ${
                activeTab === item.id 
                  ? `shadow-sm` 
                  : `hover:bg-white/10 text-white`
              }`}
              style={activeTab === item.id ? { color: COLORS.primary, backgroundColor: COLORS.card } : { color: 'rgba(255,255,255,0.8)' }}
            >
              <item.icon size={20} />
              <span className="font-bold text-sm">{item.label}</span>
            </button>
          ))}
        </nav>
      </aside>

      {/* ОСНОВНОЙ КОНТЕНТ */}
      <main className="flex-1 h-full overflow-y-auto relative pb-20 md:pb-0 scroll-smooth">
        <div className="max-w-3xl mx-auto p-4 pt-6 md:p-8">
          {activeTab === 'home' && <DashboardScreen navigate={setActiveTab} viewMode={viewMode} />}
          {activeTab === 'schedule' && <ScheduleScreen />}
          {activeTab === 'grades' && <GradesScreen />}
          {activeTab === 'mail' && <MailScreen />}
          {activeTab === 'settings' && <SettingsScreen onLogout={onLogout} isDark={isDark} toggleTheme={toggleTheme} />}
        </div>
      </main>

      {/* НИЖНЯЯ ПАНЕЛЬ НАВИГАЦИИ (Telegram Mini App / Mobile) */}
      <nav className={`${bottomNavClasses} fixed bottom-0 w-full border-t justify-around items-center pb-safe pt-2 px-2 z-50 shadow-[0_-4px_20px_rgba(0,0,0,0.05)] transition-colors duration-300`} 
           style={{ backgroundColor: COLORS.card, borderColor: COLORS.border, position: isMobileView ? 'absolute' : 'fixed' }}>
        {NAV_ITEMS.map(item => {
          const isActive = activeTab === item.id;
          return (
            <button 
              key={item.id}
              onClick={() => setActiveTab(item.id)}
              className="flex flex-col items-center p-2 w-16"
            >
              <div className={`mb-1 transition-all duration-300 ${isActive ? 'scale-110' : 'opacity-60'}`} style={{ color: isActive ? COLORS.accent : COLORS.dark }}>
                <item.icon size={24} />
              </div>
              <span className={`text-[10px] font-semibold transition-all ${isActive ? '' : 'opacity-60'}`} style={{ color: isActive ? COLORS.primary : COLORS.dark }}>
                {item.label}
              </span>
            </button>
          );
        })}
      </nav>
      
      <style dangerouslySetInnerHTML={{__html: `
        .pb-safe { padding-bottom: env(safe-area-inset-bottom, 16px); }
        .pt-safe { padding-top: env(safe-area-inset-top); }
        .scrollbar-hide::-webkit-scrollbar { display: none; }
        .scrollbar-hide { -ms-overflow-style: none; scrollbar-width: none; }
      `}} />
    </div>
  );

  // Обертка для симуляции устройства в режиме отладки
  if (isMobileView) {
    return (
      <div className="min-h-screen w-full flex items-center justify-center p-4 bg-gray-900">
        <div className="w-[390px] h-[844px] overflow-hidden rounded-[3rem] shadow-2xl ring-[14px] ring-gray-950 relative" style={{ transform: 'translateZ(0)' }}>
           {appContent}
        </div>
      </div>
    );
  }

  return appContent;
};

// Виджет для переключения режима отображения (Debugger)
const UIDebugger = ({ viewMode, setViewMode }) => (
  <div className="fixed bottom-4 right-4 z-[100] flex bg-white rounded-full shadow-lg border p-1" style={{ borderColor: '#e5e7eb' }}>
    <button onClick={() => setViewMode('mobile')} className={`p-2 rounded-full ${viewMode === 'mobile' ? 'bg-gray-200' : ''}`} title="Mobile View">
      <Icons.Smartphone size={18} color="#3b362e" />
    </button>
    <button onClick={() => setViewMode('desktop')} className={`p-2 rounded-full ${viewMode === 'desktop' ? 'bg-gray-200' : ''}`} title="Desktop View">
       <Icons.Monitor size={18} color="#3b362e" />
    </button>
    <button onClick={() => setViewMode('auto')} className={`p-2 rounded-full text-xs font-bold px-3 ${viewMode === 'auto' ? 'bg-gray-200' : ''}`} style={{ color: '#3b362e' }} title="Auto (Responsive)">
      AUTO
    </button>
  </div>
);

export default function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [activeTab, setActiveTab] = useState('home');
  const [isDark, setIsDark] = useState(false);
  const [viewMode, setViewMode] = useState('auto'); // 'auto', 'mobile', 'desktop'

  useEffect(() => {
    const timer = setTimeout(() => {
      // Имитация автологина
    }, 500);
    return () => clearTimeout(timer);
  }, []);

  const handleLogin = () => {
    setIsAuthenticated(true);
    setActiveTab('home');
  };

  const handleLogout = () => {
    setIsAuthenticated(false);
  };

  const toggleTheme = () => setIsDark(!isDark);

  // Инжектируем CSS-переменные для выбранной темы
  const themeStyles = isDark ? `
    :root {
      --color-primary: #6aaab0;
      --color-secondary: #4fa3d1;
      --color-accent: #1f5a56;
      --color-dark: #f4f7f6;
      --color-bg: #1e1b18;
      --color-card: #2a2622;
      --color-border: #3d3731;
      --color-text-muted: #a39c94;
    }
  ` : `
    :root {
      --color-primary: #1f5a56;
      --color-secondary: #036495;
      --color-accent: #6aaab0;
      --color-dark: #3b362e;
      --color-bg: #f4f7f6;
      --color-card: #ffffff;
      --color-border: #f3f4f6;
      --color-text-muted: #6b7280;
    }
  `;

  return (
    <>
      <style>{themeStyles}</style>
      {!isAuthenticated ? (
        <LoginScreen onLogin={handleLogin} />
      ) : (
        <AppShell 
          activeTab={activeTab} 
          setActiveTab={setActiveTab} 
          onLogout={handleLogout}
          isDark={isDark}
          toggleTheme={toggleTheme}
          viewMode={viewMode}
        />
      )}
      <UIDebugger viewMode={viewMode} setViewMode={setViewMode} />
    </>
  );
}