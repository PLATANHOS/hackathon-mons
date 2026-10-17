// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract UniRewards {
    enum Role { None, Student, Teacher }

    struct User { Role role; string username; string email; uint256 points; }
    struct Course { address teacher; string name; }
    struct Activity { uint256 courseId; string title; string kind; uint256 points; uint256 deadline; string file; } // deadline: 0 = sin limite
    struct Submission { bool done; bool graded; uint8 grade; string content; string file; }
    struct Msg { address sender; uint256 time; string text; }
    struct Reward { string name; uint256 cost; }
    // Logros. role None = para todos. Metricas: 0 entregas, 1 ejercicios IA, 2 quizzes IA, 3 calificaciones,
    // 4 clases (unidas o creadas), 5 actividades publicadas, 6 mejor racha IA, 7 canjes, 8 notas de 100.
    struct Achievement { string name; string desc; Role role; uint8 metric; uint256 target; uint256 bonus; }
    struct Streak { uint256 lastDay; uint256 current; }
    // Contador diario. Estudiante: a = ejercicios IA, b = quizzes IA. Profesor: a = calificaciones con puntos.
    struct Daily { uint256 day; uint8 a; uint8 b; }

    uint256 public constant EXERCISE_POINTS = 50;
    uint256 public constant QUIZ_POINTS = 120;
    uint256 public constant GRADE_POINTS = 25;
    uint256 public constant STREAK_POINTS = 20; // por cada dia de racha IA (desde el 2.o dia seguido)
    uint8 public constant MAX_STREAK_DAYS = 10;
    uint8 public constant MAX_EXERCISES = 3;
    uint8 public constant MAX_QUIZZES = 1;
    uint8 public constant MAX_GRADES = 5;

    mapping(address => User) public users;
    mapping(address => Daily) private daily;
    mapping(address => bool) private deleted; // billeteras dadas de baja (no pueden volver a registrarse)
    mapping(uint256 => mapping(address => bool)) public enrolled;
    mapping(uint256 => mapping(address => Submission)) public submissions; // actividad => estudiante
    mapping(uint256 => address[]) private students;
    mapping(uint256 => mapping(address => Msg[])) private thread; // actividad => estudiante => mensajes
    Course[] public courses;
    Activity[] public activities;
    Reward[] public rewards;
    Achievement[] public achievements;
    mapping(uint256 => mapping(address => bool)) public redeemed; // recompensa => usuario: cada quien la canjea una sola vez
    mapping(address => uint256[9]) private counters;
    mapping(address => uint256) public unlockedMask;
    mapping(address => Streak) private streaks;

    event PointsEarned(address indexed user, uint256 amount, string reason);
    event Redeemed(address indexed user, uint256 rewardId);
    event AccountDeleted(address indexed user);
    event AchievementUnlocked(address indexed user, uint256 id);

    modifier only(Role r) {
        require(users[msg.sender].role == r, "Rol no permitido");
        _;
    }

    constructor() {
        // Recompensas inventadas (no hay convenio real con las marcas)
        rewards.push(Reward("Tarjeta Steam $10 (simulada)", 6000));
        rewards.push(Reward("Bono Falabella $20 (simulado)", 8000));
        rewards.push(Reward(unicode"Bono de cafetería (simulado)", 5000));
        rewards.push(Reward(unicode"Audífonos Bluetooth (simulados)", 10000));
        // Logros: nombre, descripcion, rol, metrica, meta, puntos extra
        _ach(unicode"Primera entrega", unicode"Entrega tu primera actividad", Role.Student, 0, 1, 100);
        _ach(unicode"Estudiante constante", unicode"Entrega 10 actividades", Role.Student, 0, 10, 500);
        _ach(unicode"Imparable", unicode"Entrega 25 actividades", Role.Student, 0, 25, 1500);
        _ach(unicode"Nota perfecta", unicode"Saca 100 en una actividad", Role.Student, 8, 1, 300);
        _ach(unicode"Excelencia", unicode"Saca 100 en 5 actividades", Role.Student, 8, 5, 1000);
        _ach(unicode"Aprendiz IA", unicode"Pide 5 ejercicios al asistente", Role.Student, 1, 5, 150);
        _ach(unicode"Maestro del quiz", unicode"Completa 5 quizzes con el asistente", Role.Student, 2, 5, 400);
        _ach(unicode"Racha de 3 días", unicode"Usa el asistente 3 días seguidos", Role.Student, 6, 3, 200);
        _ach(unicode"Racha de 7 días", unicode"Usa el asistente 7 días seguidos", Role.Student, 6, 7, 700);
        _ach(unicode"Explorador", unicode"Únete a 3 clases", Role.Student, 4, 3, 250);
        _ach(unicode"Primera clase", unicode"Crea tu primera clase", Role.Teacher, 4, 1, 150);
        _ach(unicode"Docente activo", unicode"Publica 5 actividades", Role.Teacher, 5, 5, 400);
        _ach(unicode"Calificador", unicode"Califica 10 entregas", Role.Teacher, 3, 10, 500);
        _ach(unicode"Mentor", unicode"Califica 50 entregas", Role.Teacher, 3, 50, 2000);
        _ach(unicode"Primer canje", unicode"Canjea tu primera recompensa", Role.None, 7, 1, 200);
        _ach(unicode"Cazador de premios", unicode"Canjea 3 recompensas", Role.None, 7, 3, 1000);
    }

    // ---------- Cuentas y clases ----------
    function register(Role r, string calldata username, string calldata email) external {
        require(users[msg.sender].role == Role.None && r != Role.None && !deleted[msg.sender], "Registro invalido");
        users[msg.sender] = User(r, username, email, 0);
    }

    // Da de baja la cuenta. Si es un profesor, sus clases dejan de estar disponibles (ver _teacherActive).
    function deleteAccount() external {
        require(users[msg.sender].role != Role.None, "Cuenta inexistente");
        delete users[msg.sender];
        delete daily[msg.sender];
        deleted[msg.sender] = true;
        emit AccountDeleted(msg.sender);
    }

    function createCourse(string calldata name) external only(Role.Teacher) {
        courses.push(Course(msg.sender, name));
        _bump(msg.sender, 4, 1);
    }

    function joinCourse(uint256 id) external only(Role.Student) {
        require(id < courses.length && _teacherActive(id) && !enrolled[id][msg.sender], "No te puedes unir");
        enrolled[id][msg.sender] = true;
        students[id].push(msg.sender);
        _bump(msg.sender, 4, 1);
    }

    function createActivity(uint256 courseId, string memory title, string memory kind, uint256 points, uint256 deadline, string memory file)
        external only(Role.Teacher)
    {
        require(courseId < courses.length && courses[courseId].teacher == msg.sender, "No es tu clase");
        activities.push(Activity(courseId, title, kind, points, deadline, file));
        _bump(msg.sender, 5, 1);
    }

    function editActivity(uint256 id, string memory title, uint256 deadline, string memory file) external only(Role.Teacher) {
        require(courses[activities[id].courseId].teacher == msg.sender, "No es tu clase");
        Activity storage a = activities[id];
        a.title = title; a.deadline = deadline; a.file = file;
    }

    // ---------- Entregas y calificacion ----------
    // Entregar no da puntos: se otorgan al calificar, proporcionales a la nota (puntos * nota / 100).
    function submit(uint256 id, string memory content, string memory file) external only(Role.Student) {
        Activity storage a = activities[id];
        Submission storage s = submissions[id][msg.sender];
        require(_teacherActive(a.courseId) && enrolled[a.courseId][msg.sender] && !s.done, "No permitido");
        require(a.deadline == 0 || block.timestamp <= a.deadline, "Plazo vencido");
        s.done = true;
        s.content = content;
        s.file = file;
        _bump(msg.sender, 0, 1);
    }

    // El estudiante puede corregir su entrega mientras no este calificada y no venza el plazo.
    function editSubmission(uint256 id, string memory content, string memory file) external only(Role.Student) {
        Activity storage a = activities[id];
        Submission storage s = submissions[id][msg.sender];
        require(_teacherActive(a.courseId) && s.done && !s.graded, "No permitido");
        require(a.deadline == 0 || block.timestamp <= a.deadline, "Plazo vencido");
        s.content = content;
        s.file = file;
    }

    // ---------- Mensajes entre profesor y estudiante (por actividad) ----------
    // OJO: en una blockchain todo es publico; aqui solo se restringe quien escribe y quien lee desde la app.
    function postMessage(uint256 id, address student, string memory text) external {
        require(id < activities.length && bytes(text).length > 0, "Mensaje invalido");
        uint256 cid = activities[id].courseId;
        address teacher = courses[cid].teacher;
        require(enrolled[cid][student], "No permitido");
        require(
            (msg.sender == student && users[student].role == Role.Student) ||
            (msg.sender == teacher && users[teacher].role == Role.Teacher),
            "No permitido"
        );
        thread[id][student].push(Msg(msg.sender, block.timestamp, text));
    }

    function getMessages(uint256 id, address student) external view returns (Msg[] memory) {
        require(msg.sender == student || msg.sender == courses[activities[id].courseId].teacher, "No permitido");
        return thread[id][student];
    }

    // El profesor puede calificar sin limite, pero solo las 5 primeras del dia dan puntos.
    function grade(uint256 id, address student, uint8 score) external only(Role.Teacher) {
        require(courses[activities[id].courseId].teacher == msg.sender, "No es tu clase");
        Submission storage s = submissions[id][student];
        require(s.done && !s.graded && score <= 100, "No calificable");
        s.graded = true;
        s.grade = score;
        uint256 pts = activities[id].points * score / 100;
        if (pts > 0 && users[student].role == Role.Student) _earn(student, pts, "Actividad calificada");
        if (score == 100 && users[student].role == Role.Student) _bump(student, 8, 1);
        Daily storage d = _today(msg.sender);
        if (d.a < MAX_GRADES) {
            d.a++;
            _earn(msg.sender, GRADE_POINTS, "Calificacion");
        }
        _bump(msg.sender, 3, 1);
    }

    // ---------- Agente IA (la IA corre fuera de la cadena; aqui solo se limitan y premian los usos) ----------
    function aiExercise() external only(Role.Student) {
        Daily storage d = _today(msg.sender);
        require(d.a < MAX_EXERCISES, "Limite diario de ejercicios");
        d.a++;
        _earn(msg.sender, EXERCISE_POINTS, "Ejercicio IA");
        _streak(msg.sender);
        _bump(msg.sender, 1, 1);
    }

    function aiQuiz() external only(Role.Student) {
        Daily storage d = _today(msg.sender);
        require(d.b < MAX_QUIZZES, "Ya hiciste el quiz de hoy");
        d.b++;
        _earn(msg.sender, QUIZ_POINTS, "Quiz IA");
        _streak(msg.sender);
        _bump(msg.sender, 2, 1);
    }

    // ---------- Recompensas ----------
    // Cada recompensa se canjea una sola vez por cuenta (otros usuarios si pueden canjearla).
    function redeem(uint256 id) external {
        require(users[msg.sender].role != Role.None, "Cuenta inexistente");
        require(id < rewards.length, "Recompensa invalida");
        require(!redeemed[id][msg.sender], "Ya canjeaste esta recompensa");
        Reward storage r = rewards[id];
        require(users[msg.sender].points >= r.cost, "Puntos insuficientes");
        users[msg.sender].points -= r.cost;
        redeemed[id][msg.sender] = true;
        emit Redeemed(msg.sender, id);
        _bump(msg.sender, 7, 1);
    }

    // ---------- Lectura ----------
    function courseCount() external view returns (uint256) { return courses.length; }
    function activityCount() external view returns (uint256) { return activities.length; }
    function rewardCount() external view returns (uint256) { return rewards.length; }
    function getStudents(uint256 id) external view returns (address[] memory) { return students[id]; }

    function achCount() external view returns (uint256) { return achievements.length; }
    function getCounters(address u) external view returns (uint256[9] memory) { return counters[u]; }

    // Dias seguidos usando el asistente IA (0 si se rompio la racha).
    function currentStreak(address u) external view returns (uint256) {
        Streak memory s = streaks[u];
        uint256 t = block.timestamp / 1 days;
        return (s.lastDay == t || (s.lastDay != 0 && s.lastDay + 1 == t)) ? s.current : 0;
    }

    function todayStats(address u) external view returns (uint8, uint8) {
        Daily memory d = daily[u];
        return d.day == block.timestamp / 1 days ? (d.a, d.b) : (uint8(0), uint8(0));
    }

    // ---------- Internas ----------
    // Una clase solo esta activa mientras la cuenta de su profesor exista.
    function _teacherActive(uint256 courseId) internal view returns (bool) {
        return users[courses[courseId].teacher].role == Role.Teacher;
    }

    function _today(address u) internal returns (Daily storage d) {
        d = daily[u];
        uint256 t = block.timestamp / 1 days;
        if (d.day != t) { d.day = t; d.a = 0; d.b = 0; }
    }

    function _ach(string memory n, string memory d, Role r, uint8 m, uint256 t, uint256 b) internal {
        achievements.push(Achievement(n, d, r, m, t, b));
    }

    // Suma al contador de una metrica y desbloquea los logros que ya se cumplieron (cada uno da puntos extra).
    function _bump(address u, uint8 metric, uint256 by) internal {
        counters[u][metric] += by;
        _check(u, metric);
    }

    function _check(address u, uint8 metric) internal {
        Role r = users[u].role;
        uint256 mask = unlockedMask[u];
        for (uint256 i = 0; i < achievements.length; i++) {
            if (((mask >> i) & 1) == 1) continue;
            Achievement storage a = achievements[i];
            if (a.metric != metric || (a.role != Role.None && a.role != r)) continue;
            if (counters[u][metric] >= a.target) {
                mask |= (uint256(1) << i);
                unlockedMask[u] = mask;
                _earn(u, a.bonus, string.concat("Logro: ", a.name));
                emit AchievementUnlocked(u, i);
            }
        }
    }

    // Racha diaria con el asistente: desde el 2.o dia seguido da STREAK_POINTS por cada dia de racha (maximo 10 dias).
    function _streak(address u) internal {
        Streak storage s = streaks[u];
        uint256 t = block.timestamp / 1 days;
        if (s.lastDay == t) return;
        s.current = (s.lastDay != 0 && s.lastDay + 1 == t) ? s.current + 1 : 1;
        s.lastDay = t;
        if (s.current >= 2) {
            uint256 d = s.current > uint256(MAX_STREAK_DAYS) ? uint256(MAX_STREAK_DAYS) : s.current;
            _earn(u, STREAK_POINTS * d, "Racha IA");
        }
        if (s.current > counters[u][6]) { counters[u][6] = s.current; _check(u, 6); }
    }

    function _earn(address u, uint256 amount, string memory reason) internal {
        users[u].points += amount;
        emit PointsEarned(u, amount, reason);
    }
}
