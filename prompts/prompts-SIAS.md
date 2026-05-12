# Prompts iniciales — Modelo de datos LTI

Documentación de los prompts utilizados con GitHub Copilot (Claude Sonnet 4.6)
para diseñar e implementar el modelo de datos del ATS de LTI.

---

## 1. Análisis del ERD frente al schema existente

```text
Analiza el schema.prisma actual ubicado en backend/prisma/schema.prisma 
y el ERD en formato Mermaid que te proporciono a continuación.

[ERD Mermaid con entidades: COMPANY, EMPLOYEE, POSITION, INTERVIEW_FLOW,
INTERVIEW_STEP, INTERVIEW_TYPE, CANDIDATE, APPLICATION, INTERVIEW]

Dime:
1. Qué modelos/tablas ya existen en el schema actual
2. Qué entidades nuevas hay en el ERD que no están en el schema
3. Qué relaciones existen entre las entidades nuevas y las ya existentes
4. Qué violaciones de normalización (1FN, 2FN, 3FN) detectas en el ERD
   tal como está definido
```

**Resultado obtenido:** El asistente identificó que el schema existente solo
cubría `Candidate`, `Education`, `WorkExperience` y `Resume` (25% del dominio),
listó las 8 entidades nuevas necesarias y detectó tres violaciones de
normalización en el ERD original:

- `POSITION.company_description` — dependencia transitiva (3FN)
- `POSITION.contact_info` — campo no atómico (1FN)
- `EMPLOYEE.role` — string libre sin tabla de catálogo (integridad referencial)

---

## 2. Decisiones de diseño

A partir del análisis, se tomaron tres decisiones que condicionaron todo el
diseño posterior:

| Decisión | Detalle |
|---|---|
| Conservar modelos existentes | `Education`, `WorkExperience` y `Resume` se mantienen e integran |
| Normalizar `company_description` | Se mueve a `Company.description` (dependía del `company_id`, no del `position.id`) |
| Tablas de catálogo | Estados y tipos se modelan como tablas referenciadas, no como enums ni strings libres |

---

## 3. Diseño normalizado (hasta 3FN)

```text
Basándote en el análisis anterior, diseña la estructura normalizada 
para las nuevas entidades del ERD siguiendo estas reglas:

NORMALIZACIÓN:
- Aplica hasta 3FN como mínimo
- Identifica y elimina dependencias transitivas
- Separa en tablas auxiliares cualquier dato que se repita
- Usa tipos de dato precisos (no uses String para todo)

ÍNDICES (aplica las siguientes reglas):
- Crea índices B-tree en todas las columnas que aparezcan en 
  WHERE, JOIN, ORDER BY o GROUP BY frecuentes
- Añade índice único donde el negocio lo requiera
- Justifica cada índice que propongas

CLAVES Y RELACIONES:
- Define correctamente todas las FK
- Añade restricciones CHECK donde tenga sentido de negocio
- Usa UUID o autoincrement según el patrón ya usado en el proyecto

Devuélveme el diseño en formato de tabla con: 
nombre de tabla, columnas, tipos, restricciones e índices propuestos.
```

### Tablas de catálogo generadas (5)

| Tabla | Valores semilla |
|---|---|
| `EmployeeRole` | `RECRUITER`, `INTERVIEWER`, `MANAGER`, `ADMIN` |
| `PositionStatus` | `DRAFT`, `OPEN`, `CLOSED`, `CANCELLED` |
| `EmploymentType` | `FULL_TIME`, `PART_TIME`, `CONTRACT`, `INTERNSHIP`, `FREELANCE` |
| `ApplicationStatus` | `PENDING`, `REVIEWING`, `INTERVIEW`, `OFFER`, `HIRED`, `REJECTED` |
| `InterviewResult` | `PENDING`, `PASS`, `FAIL`, `NO_SHOW` |

### Entidades principales generadas (7 nuevas)

`Company` · `Employee` · `InterviewType` · `InterviewFlow` · `InterviewStep` ·
`Position` · `Application` · `Interview`

### Normalización aplicada

| Violación original | Corrección aplicada | Forma normal |
|---|---|---|
| `POSITION.company_description` dependía de `company_id` | Movido a `Company.description` | 3FN |
| `POSITION.contact_info` era un string no atómico | Reemplazado por FK `contactEmployeeId → Employee` | 1FN |
| `EMPLOYEE.role` era un string libre | Reemplazado por FK `roleId → EmployeeRole` | Integridad referencial |
| `INTERVIEW.result` podría derivarse de `score` | `result` e `score` son campos independientes; `result` referencia catálogo | 3FN |
| `APPLICATION.status`, `POSITION.status`, etc. eran strings | Todos reemplazados por FK a sus respectivas tablas de catálogo | Integridad referencial |

### Índices añadidos y justificación

| Tabla | Columna(s) | Tipo | Justificación |
|---|---|---|---|
| `Company` | `name` | B-tree | Búsquedas y filtros por nombre en listados |
| `Employee` | `companyId` | B-tree | JOIN frecuente con Company |
| `Employee` | `roleId` | B-tree | `WHERE roleId = ?` para listar por rol |
| `Employee` | `isActive` | B-tree | Casi todas las queries excluyen inactivos |
| `InterviewStep` | `(interviewFlowId, orderIndex)` | UNIQUE | Orden único por flujo; cubre `ORDER BY` |
| `InterviewStep` | `interviewTypeId` | B-tree | JOIN para obtener el tipo de cada paso |
| `Position` | `companyId` | B-tree | Listado de posiciones de una empresa |
| `Position` | `interviewFlowId` | B-tree | JOIN al cargar configuración de entrevistas |
| `Position` | `statusId` | B-tree | `WHERE status = OPEN` — query más frecuente |
| `Position` | `isVisible` | B-tree | Filtro del portal público |
| `Position` | `applicationDeadline` | B-tree | `ORDER BY` y alertas de vencimiento |
| `Position` | `employmentTypeId` | B-tree | Faceta de búsqueda de empleo |
| `Position` | `contactEmployeeId` | B-tree | Consulta inversa: posiciones por contacto |
| `Application` | `(positionId, candidateId)` | UNIQUE | Regla de negocio: sin candidaturas duplicadas |
| `Application` | `candidateId` | B-tree | Historial de candidaturas de un candidato |
| `Application` | `statusId` | B-tree | Filtros de pipeline en dashboard |
| `Application` | `applicationDate` | B-tree | `ORDER BY` en listados recientes |
| `Interview` | `applicationId` | B-tree | JOIN principal: entrevistas de una candidatura |
| `Interview` | `interviewStepId` | B-tree | JOIN para el paso del flujo |
| `Interview` | `interviewerId` | B-tree | Agenda del entrevistador |
| `Interview` | `interviewDate` | B-tree | `ORDER BY` en agenda y alertas |
| `Interview` | `resultId` | B-tree | Reporting por resultado |

### CHECK constraints añadidos (no generados por Prisma)

```sql
-- Coherencia salarial
ALTER TABLE "Position"
    ADD CONSTRAINT "Position_salaryMin_check"
        CHECK ("salaryMin" IS NULL OR "salaryMin" >= 0),
    ADD CONSTRAINT "Position_salaryRange_check"
        CHECK ("salaryMax" IS NULL OR "salaryMin" IS NULL
               OR "salaryMax" >= "salaryMin");

-- Puntuación en escala 0–10
ALTER TABLE "Interview"
    ADD CONSTRAINT "Interview_score_check"
        CHECK ("score" IS NULL OR ("score" >= 0 AND "score" <= 10));
```

---

## 4. Generación del schema Prisma

```text
Convierte el diseño normalizado anterior a modelos Prisma válidos 
para añadir al archivo schema.prisma existente.

Requisitos:
- Usa la sintaxis correcta de Prisma (@@index, @@unique, @relation)
- Añade @@index para todas las columnas identificadas en el paso anterior
- Respeta las convenciones de nombres ya usadas en el schema actual 
  (camelCase en Prisma, snake_case en la DB si ya se usa así)
- Incluye los campos createdAt y updatedAt con @default(now()) 
  y @updatedAt donde corresponda
- No modifiques los modelos existentes, solo añade los nuevos

Devuelve únicamente el bloque de código con los modelos nuevos 
listos para pegar en schema.prisma.
```

**Ajuste necesario detectado:** Prisma requiere back-references bidireccionales.
Se añadió `applications Application[]` al modelo `Candidate` existente — único
cambio en modelos preexistentes, no destructivo.

---

## 5. Generación de la migración SQL

```text
Genera el script SQL equivalente a los modelos Prisma anteriores, 
compatible con PostgreSQL.

El script debe incluir:
1. CREATE TABLE con todos los tipos de dato nativos de PostgreSQL
2. PRIMARY KEY, FOREIGN KEY y UNIQUE constraints
3. CREATE INDEX para cada @@index definido en Prisma
4. Comentarios explicando cada tabla y sus índices
5. Las sentencias en orden correcto para respetar las FK 
   (las tablas referenciadas primero)

Añade al final 3-5 INSERT de ejemplo por tabla principal 
para poder verificar la estructura en DBeaver.
```

---

## 6. Implementación y migración aplicada

```text
Start implementation
```

La implementación se realizó en los siguientes pasos:

1. Se actualizó `backend/prisma/schema.prisma` con los 12 modelos nuevos
2. Se ejecutó `npx prisma migrate dev --name ats_full_schema`
   → Migración `20260511213704_ats_full_schema` aplicada
3. Se añadieron los CHECK constraints y se sembraron los catálogos
   vía `npx prisma db execute`
4. Se generó el archivo de referencia con patrón expand-contract en
   `migrations/20260511233853_add-job-application-flow/migration.sql`
5. Tras auditoría del conjunto, se detectaron 4 índices FK faltantes
   y se corrigieron en una migración adicional
   (`20260511233853_add-job-application-flow`)

### Historial de migraciones resultante

| Migración | Contenido |
|---|---|
| `20260511000000_initial_schema` | Schema base inicial |
| `20260511212242_primera` | Modelos `Candidate`, `Education`, `WorkExperience`, `Resume` |
| `20260511213704_ats_full_schema` | 12 modelos ATS nuevos + todos sus índices y FK |
| `20260511233853_add-job-application-flow` | 4 índices FK faltantes + CHECK constraints |

---

## 7. Auditoría final

```text
Revisa el conjunto completo: schema.prisma actualizado + migration.sql 
y comprueba que:

1. NORMALIZACIÓN: no hay dependencias transitivas ni datos repetidos
2. ÍNDICES: todas las FK tienen índice, las columnas de búsqueda frecuente 
   también
3. CONSISTENCIA: los tipos en Prisma y en el SQL coinciden
4. INTEGRIDAD: todas las relaciones tienen ON DELETE definido 
   (CASCADE, RESTRICT o SET NULL según el caso de negocio)
5. SEGURIDAD: no hay campos sensibles sin considerar (passwords, tokens)

Lista cualquier problema encontrado y propón la corrección.
```

**Problemas encontrados y corregidos:**

| # | Problema | Corrección |
|---|---|---|
| 1 | 4 columnas FK sin índice (`InterviewStep.interviewTypeId`, `Position.interviewFlowId`, `Position.contactEmployeeId`, `Interview.interviewStepId`) | Añadidos en migración `add-job-application-flow` |

**Observaciones de seguridad pendientes (fuera de scope de migración):**

| Campo | Riesgo | Acción recomendada |
|---|---|---|
| `Resume.filePath` | Path traversal si se expone sin sanitizar | Validar en capa de servicio que la ruta esté bajo el directorio permitido |
| `Candidate` (email, phone, address) | PII sin estrategia de borrado (GDPR art. 17) | Añadir `deletedAt` para soft-delete + proceso de anonimización |
