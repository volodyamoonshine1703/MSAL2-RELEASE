/**
 * MSAL+ API Client для работы с бэкендом МГЮА
 * Base URL: https://lk.msal.ru:3443
 */

const BASE_URL = 'https://lk.msal.ru:3443';

// Стандартные заголовки для всех запросов
const getDefaultHeaders = (token) => ({
  'Accept': 'application/json, text/plain, */*',
  'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
  'Content-Type': 'application/json',
  'Origin': 'https://lk.msal.ru',
  'Referer': 'https://lk.msal.ru/',
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:150.0) Gecko/20100101 Firefox/150.0',
  'X-Device-Model': 'ClientType: browser, ClientName: Firefox, ClientVersion: 151.0, DeviceOS: Windows, DeviceType: desktop',
  ...(token ? { 'Authorization': `Bearer ${token}` } : {})
});

/**
 * Универсальная функция для HTTP запросов
 */
async function request(endpoint, options = {}, token = null) {
  const url = `${BASE_URL}${endpoint}`;
  const headers = getDefaultHeaders(token);
  
  const config = {
    ...options,
    headers: {
      ...headers,
      ...options.headers
    }
  };

  try {
    const response = await fetch(url, config);
    
    // Обработка 401 - токен недействителен
    if (response.status === 401) {
      throw new Error('UNAUTHORIZED');
    }
    
    // Пустой ответ
    if (response.status === 204 || !response.body) {
      return null;
    }
    
    const data = await response.json();
    return data;
  } catch (error) {
    console.error(`API Error (${endpoint}):`, error);
    throw error;
  }
}

/**
 * AuthService - управление аутентификацией
 */
export const authService = {
  /**
   * Логин пользователя
   * POST /auth
   */
  async login(username, password) {
    const data = await request('/auth', {
      method: 'POST',
      body: JSON.stringify({ username, password })
    });
    
    if (data && data.access_token) {
      localStorage.setItem('access_token', data.access_token);
      localStorage.setItem('refresh_token', data.refresh_token);
      localStorage.setItem('saved_login', username);
    }
    
    return data;
  },

  /**
   * Проверка сессии
   * GET /auth
   */
  async checkSession(token) {
    return request('/auth', { method: 'GET' }, token);
  },

  /**
   * Обновление токена
   * POST /auth/refresh
   */
  async refreshToken(refreshToken) {
    const data = await request('/auth/refresh', {
      method: 'POST',
      body: JSON.stringify({ refresh_token: refreshToken })
    });
    
    if (data && data.access_token) {
      localStorage.setItem('access_token', data.access_token);
      if (data.refresh_token) {
        localStorage.setItem('refresh_token', data.refresh_token);
      }
    }
    
    return data;
  },

  /**
   * Логаут
   * POST /auth/logout
   */
  async logout(token) {
    try {
      await request('/auth/logout', { method: 'POST' }, token);
    } catch (e) {
      // Игнорируем ошибки при логауте
    }
    
    localStorage.removeItem('access_token');
    localStorage.removeItem('refresh_token');
    localStorage.removeItem('saved_login');
    localStorage.removeItem('cached_user');
  },

  /**
   * Получение сохранённых данных пользователя
   */
  getCachedUser() {
    const cached = localStorage.getItem('cached_user');
    return cached ? JSON.parse(cached) : null;
  },

  /**
   * Сохранение данных пользователя в кеш
   */
  cacheUser(userData) {
    localStorage.setItem('cached_user', JSON.stringify(userData));
  },

  /**
   * Восстановление сессии
   */
  async restoreSession() {
    const token = localStorage.getItem('access_token');
    const refreshToken = localStorage.getItem('refresh_token');
    const savedLogin = localStorage.getItem('saved_login');

    if (!token && !refreshToken) {
      return null;
    }

    // Проверяем текущий токен
    if (token) {
      try {
        const user = await this.checkSession(token);
        if (user) {
          this.cacheUser(user);
          return { user, token };
        }
      } catch (e) {
        // Токен истёк, пробуем refresh
      }
    }

    // Пробуем обновить через refresh token
    if (refreshToken) {
      try {
        const data = await this.refreshToken(refreshToken);
        if (data && data.access_token) {
          const user = await this.checkSession(data.access_token);
          if (user) {
            this.cacheUser(user);
            return { user, token: data.access_token };
          }
        }
      } catch (e) {
        // Refresh не сработал
      }
    }

    return null;
  }
};

/**
 * ApiService - работа с личным кабинетом
 */
export const apiService = {
  /**
   * Получить расписание на неделю
   * GET /schedule?from=YYYY-MM-DD&to=YYYY-MM-DD
   */
  async getScheduleWeek(monday, token) {
    const from = monday.toISOString().split('T')[0];
    const sunday = new Date(monday);
    sunday.setDate(monday.getDate() + 6);
    const to = sunday.toISOString().split('T')[0];
    
    return request(`/schedule?from=${from}&to=${to}`, {}, token);
  },

  /**
   * Получить успеваемость
   * GET /progress?course=X&semester=Y
   */
  async getProgress(course, semester, token) {
    return request(`/progress?course=${course}&semester=${semester}`, {}, token);
  },

  /**
   * Получить детали успеваемости по дисциплине
   * GET /progress/details?disciplineID=UUID&course=X&semester=Y
   */
  async getProgressDetails(disciplineId, course, semester, token) {
    return request(`/progress/details?disciplineID=${disciplineId}&course=${course}&semester=${semester}`, {}, token);
  },

  /**
   * Получить зачётную книжку
   * GET /recordbook
   */
  async getRecordbook(token) {
    return request('/recordbook', {}, token);
  },

  /**
   * Получить группу студента
   * GET /student/group
   */
  async getGroupmates(token) {
    return request('/student/group', {}, token);
  },

  /**
   * Получить информацию о студенте (институт)
   * GET /student/info
   */
  async getStudentInfo(token) {
    return request('/student/info', {}, token);
  },

  /**
   * Получить домашнее задание
   * GET /homework/{lessonId}
   */
  async getHomework(lessonId, token) {
    return request(`/homework/${lessonId}`, {}, token);
  },

  /**
   * Получить мои консультации
   * GET /consultation/my?from=...&to=...
   */
  async getMyConsultations(from, to, token) {
    return request(`/consultation/my?from=${from}&to=${to}`, {}, token);
  },

  /**
   * Записаться на консультацию
   * POST /consultation
   */
  async bookConsultation(consultationData, token) {
    return request('/consultation', {
      method: 'POST',
      body: JSON.stringify(consultationData)
    }, token);
  },

  /**
   * Отменить консультацию
   * PATCH /consultation
   */
  async cancelConsultation(consultationData, token) {
    return request('/consultation', {
      method: 'PATCH',
      body: JSON.stringify(consultationData)
    }, token);
  },

  /**
   * Получить новости
   * GET /news/preview
   */
  async getNews(token) {
    return request('/news/preview', {}, token);
  },

  /**
   * Отметить новость как прочитанную
   * POST /news/{id}/read
   */
  async markNewsRead(newsId, token) {
    return request(`/news/${newsId}/read`, { method: 'POST' }, token);
  },

  /**
   * Обновить настройки приватности
   * PUT /student/access
   */
  async updatePrivacySettings(settings, token) {
    return request('/student/access', {
      method: 'PUT',
      body: JSON.stringify(settings)
    }, token);
  },

  /**
   * Получить список дисциплин
   * GET /disciplines/student
   */
  async getDisciplines(token) {
    return request('/disciplines/student', {}, token);
  },

  /**
   * Получить преподавателей дисциплины
   * GET /disciplines/{id}/teachers
   */
  async getDisciplineTeachers(disciplineId, token) {
    return request(`/disciplines/${disciplineId}/teachers`, {}, token);
  }
};

/**
 * MailService - работа с почтой (через прокси или прямой доступ)
 * Для веб-версии потребуется backend-proxy из-за CORS и IMAP/SMTP
 */
export const mailService = {
  // Почтовые сервисы требуют серверной части для работы с IMAP/SMTP
  // В веб-версии используем прокси-эндпоинты
  
  async listFolders(token) {
    // Требуется прокси для IMAP
    console.warn('Mail folders requires backend proxy');
    return [];
  },

  async fetchMessages(folder, limit = 50, token) {
    // Требуется прокси для IMAP
    console.warn('Mail fetch requires backend proxy');
    return [];
  },

  async sendMessage(data, token) {
    // Требуется прокси для SMTP/OWA
    console.warn('Mail send requires backend proxy');
    return false;
  }
};

export default {
  auth: authService,
  api: apiService,
  mail: mailService
};
