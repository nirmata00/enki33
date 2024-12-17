-- Tabla de usuarios (integrada con Supabase Auth)
CREATE TABLE public.app_user (
    id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email text NOT NULL,
    full_name text NOT NULL,
    avatar_url text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    CONSTRAINT app_user_email_key UNIQUE (email)
);

-- Política de seguridad RLS (Row Level Security)
ALTER TABLE public.app_user ENABLE ROW LEVEL SECURITY;

-- Políticas para app_user
CREATE POLICY "Users can view their own profile"
    ON public.app_user
    FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
    ON public.app_user
    FOR UPDATE
    USING (auth.uid() = id);

-- Tabla de organizaciones
CREATE TABLE public.organization (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    code varchar(20) NOT NULL UNIQUE,
    name text NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    CONSTRAINT organization_name_unique UNIQUE (name),
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE
);

-- Tabla de monedas
CREATE TABLE public.currency (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    code varchar(3) NOT NULL UNIQUE,
    name text NOT NULL,
    symbol varchar(5),
    is_active boolean NOT NULL DEFAULT true,
    is_default boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    CONSTRAINT unique_default_currency CHECK (
        CASE WHEN is_default THEN 1 ELSE 0 END = (
            SELECT COUNT(*) FROM public.currency c2 
            WHERE c2.is_default AND 
            (c2.id = id OR NOT EXISTS (SELECT 1 FROM public.currency WHERE is_default))
        )
    )
);

-- Tabla de jarras de presupuesto
CREATE TABLE public.budget_jar (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    percentage numeric(5,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    CONSTRAINT check_percentage CHECK (percentage >= 0 AND percentage <= 100),
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE
);

-- Tabla de categorías
CREATE TABLE public.category (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE
);

-- Tabla de subcategorías
CREATE TABLE public.sub_category (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    category_id uuid NOT NULL REFERENCES public.category(id) ON DELETE CASCADE,
    budget_jar_id uuid NOT NULL DEFAULT (SELECT id FROM public.budget_jar WHERE name = 'UNDEFINED')
        REFERENCES public.budget_jar(id) ON DELETE SET DEFAULT,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE
);

-- Tabla de histórico de cambios en subcategorías
CREATE TABLE public.sub_category_history (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    sub_category_id uuid NOT NULL REFERENCES public.sub_category(id) ON DELETE CASCADE,
    old_category_id uuid REFERENCES public.category(id) ON DELETE SET NULL,
    new_category_id uuid REFERENCES public.category(id) ON DELETE SET NULL,
    old_budget_jar_id uuid REFERENCES public.budget_jar(id) ON DELETE SET NULL,
    new_budget_jar_id uuid REFERENCES public.budget_jar(id) ON DELETE SET NULL,
    change_date timestamptz DEFAULT CURRENT_TIMESTAMP,
    change_type varchar(20) NOT NULL CHECK (change_type IN ('CATEGORY_CHANGE', 'JAR_CHANGE', 'BOTH')),
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    is_active boolean NOT NULL DEFAULT true
);

-- Tabla de tipos de transacción
CREATE TABLE public.transaction_type (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de medios de transacción
CREATE TABLE public.transaction_medium (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de cuentas
CREATE TABLE public.account (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    initial_balance numeric(15,2) NOT NULL DEFAULT 0,
    currency_id uuid NOT NULL DEFAULT (SELECT id FROM public.currency WHERE code = 'UND') 
        REFERENCES public.currency(id) ON DELETE SET DEFAULT DEFAULT (SELECT id FROM public.currency WHERE code = 'UND'),
    is_active boolean NOT NULL DEFAULT true,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla de períodos
CREATE TABLE public.period (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    start_date date NOT NULL,
    end_date date NOT NULL,
    name text NOT NULL,
    is_closed boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_period_dates CHECK (end_date >= start_date),
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    is_active boolean NOT NULL DEFAULT true
);

-- Tabla de ingresos por período
CREATE TABLE public.period_income (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    period_id uuid NOT NULL REFERENCES public.period(id) ON DELETE CASCADE,
    total_income numeric(15,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    CONSTRAINT unique_period_income UNIQUE (period_id),
    CONSTRAINT check_income_positive CHECK (total_income >= 0),
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    is_active boolean NOT NULL DEFAULT true
);

-- Tabla de presupuestos por jarra y período
CREATE TABLE public.jar_period_budget (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    period_id uuid NOT NULL REFERENCES public.period(id) ON DELETE CASCADE,
    budget_jar_id uuid NOT NULL REFERENCES public.budget_jar(id) ON DELETE CASCADE,
    calculated_amount numeric(15,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_jar_period UNIQUE (period_id, budget_jar_id),
    CONSTRAINT check_amount_positive CHECK (calculated_amount >= 0),
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    is_active boolean NOT NULL DEFAULT true
);

-- Tabla de transacciones
CREATE TABLE public.transaction (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    registered_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    date date NOT NULL,
    amount numeric(15, 2) NOT NULL,
    scheduled_amount numeric(15, 2),
    amount_variation numeric(15, 2) GENERATED ALWAYS AS (
        COALESCE(amount - scheduled_amount, NULL)
    ) STORED,
    currency_id uuid NOT NULL DEFAULT (SELECT id FROM public.currency WHERE code = 'UND')
        REFERENCES public.currency(id) ON DELETE SET DEFAULT,
    organization_id uuid NOT NULL DEFAULT (SELECT id FROM public.organization WHERE code = 'UND')
        REFERENCES public.organization(id) ON DELETE SET DEFAULT,
    tags jsonb,
    notes text,
    reference varchar(100),
    category uuid NOT NULL DEFAULT (SELECT id FROM public.category WHERE name = 'UNDEFINED')
        REFERENCES public.category(id) ON DELETE SET DEFAULT,
    sub_category uuid NOT NULL DEFAULT (SELECT id FROM public.sub_category WHERE name = 'UNDEFINED')
        REFERENCES public.sub_category(id) ON DELETE SET DEFAULT,
    account uuid NOT NULL REFERENCES public.account(id) ON DELETE CASCADE,
    transaction_type uuid NOT NULL DEFAULT (SELECT id FROM public.transaction_type WHERE name = 'UNDEFINED')
        REFERENCES public.transaction_type(id) ON DELETE SET DEFAULT,
    transaction_medium uuid DEFAULT (SELECT id FROM public.transaction_medium WHERE name = 'UNDEFINED')
        REFERENCES public.transaction_medium(id) ON DELETE SET DEFAULT,
    is_expense boolean NOT NULL DEFAULT true,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    is_foreign_currency boolean NOT NULL DEFAULT false,
    -- Campos para transacciones recurrentes
    is_recurrent boolean NOT NULL DEFAULT false,
    recurrence_group_id uuid,
    frequency_id uuid REFERENCES public.recurrence_frequency(id),
    execution_day smallint,
    cut_day smallint,
    payment_day smallint,
    start_date date,
    end_date date,
    next_execution_date date,
    recurrence_status varchar(20) DEFAULT 'ACTIVE' 
        CHECK (recurrence_status IN ('ACTIVE', 'PAUSED', 'CANCELLED')),
    execution_count integer DEFAULT 0,
    max_executions integer,
    CONSTRAINT check_amount_not_zero CHECK (amount != 0),
    CONSTRAINT check_scheduled_amount_not_zero CHECK (scheduled_amount != 0 OR scheduled_amount IS NULL),
    CONSTRAINT check_execution_day CHECK (execution_day BETWEEN 1 AND 31),
    CONSTRAINT check_cut_day CHECK (cut_day BETWEEN 1 AND 31),
    CONSTRAINT check_payment_day CHECK (payment_day BETWEEN 1 AND 31)
);


-- Tabla de histórico de cambios en transacciones
CREATE TABLE public.transaction_history (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    transaction_id uuid NOT NULL REFERENCES public.transaction(id) ON DELETE CASCADE,
    change_date timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    change_type varchar(20) NOT NULL CHECK (
        change_type IN (
            'CURRENCY', 
            'ORGANIZATION', 
            'CATEGORY', 
            'SUBCATEGORY', 
            'ACCOUNT', 
            'TRANSACTION_TYPE', 
            'TRANSACTION_MEDIUM'
        )
    ),
    -- Campos para cambios en moneda
    old_currency_id uuid REFERENCES public.currency(id) ON DELETE SET NULL,
    new_currency_id uuid REFERENCES public.currency(id) ON DELETE SET NULL,
    -- Campos para cambios en organización
    old_organization_id uuid REFERENCES public.organization(id) ON DELETE SET NULL,
    new_organization_id uuid REFERENCES public.organization(id) ON DELETE SET NULL,
    -- Campos para cambios en categoría
    old_category_id uuid REFERENCES public.category(id) ON DELETE SET NULL,
    new_category_id uuid REFERENCES public.category(id) ON DELETE SET NULL,
    -- Campos para cambios en subcategoría
    old_subcategory_id uuid REFERENCES public.sub_category(id) ON DELETE SET NULL,
    new_subcategory_id uuid REFERENCES public.sub_category(id) ON DELETE SET NULL,
    -- Campos para cambios en cuenta
    old_account_id uuid REFERENCES public.account(id) ON DELETE SET NULL,
    new_account_id uuid REFERENCES public.account(id) ON DELETE SET NULL,
    -- Campos para cambios en tipo de transacción
    old_transaction_type_id uuid REFERENCES public.transaction_type(id) ON DELETE SET NULL,
    new_transaction_type_id uuid REFERENCES public.transaction_type(id) ON DELETE SET NULL,
    -- Campos para cambios en medio de transacción
    old_transaction_medium_id uuid REFERENCES public.transaction_medium(id) ON DELETE SET NULL,
    new_transaction_medium_id uuid REFERENCES public.transaction_medium(id) ON DELETE SET NULL,
    -- Usuario que realizó el cambio
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    notes text
);

-- Tabla para manejar transferencias entre cuentas
CREATE TABLE public.account_transfer (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    amount numeric(15,2) NOT NULL,
    from_account_id uuid NOT NULL REFERENCES public.account(id),
    to_account_id uuid NOT NULL REFERENCES public.account(id),
    from_transaction_id uuid NOT NULL REFERENCES public.transaction(id),
    to_transaction_id uuid NOT NULL REFERENCES public.transaction(id),
    transfer_date date NOT NULL,
    exchange_rate numeric(20,6) DEFAULT 1.0,
    notes text,
    user_id uuid NOT NULL REFERENCES public.app_user(id),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT different_accounts CHECK (from_account_id != to_account_id),
    CONSTRAINT check_transfer_amount CHECK (amount > 0),
    CONSTRAINT check_exchange_rate CHECK (exchange_rate > 0)
);

-- Tabla para registrar transacciones en moneda extranjera
CREATE TABLE public.foreign_currency_transaction (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    transaction_id uuid NOT NULL REFERENCES public.transaction(id) ON DELETE CASCADE,
    original_amount numeric(15,2) NOT NULL,
    original_currency_id uuid NOT NULL REFERENCES public.currency(id) ON DELETE CASCADE,
    exchange_rate numeric(20,6) NOT NULL,
    transaction_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_exchange_rate_positive CHECK (exchange_rate > 0),
    CONSTRAINT check_original_amount_not_zero CHECK (original_amount != 0)
);

-- Tabla para frecuencias de recurrencia
CREATE TABLE public.recurrence_frequency (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    interval_value interval NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

-- Tabla para agrupar transacciones recurrentes
CREATE TABLE public.recurrence_group (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    description text NOT NULL,
    template_transaction_id uuid NOT NULL REFERENCES public.transaction(id),
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE
);

-- Crear índices
CREATE INDEX idx_transaction_organization_id ON public.transaction(organization_id);
CREATE INDEX idx_transaction_date ON public.transaction(date);
CREATE INDEX idx_transaction_user_id ON public.transaction(user_id);
CREATE INDEX idx_transaction_account ON public.transaction(account);
CREATE INDEX idx_transaction_category ON public.transaction(category);
CREATE INDEX idx_transaction_sub_category ON public.transaction(sub_category);
CREATE INDEX idx_transaction_is_recurrent ON public.transaction(is_recurrent);
CREATE INDEX idx_transaction_recurrence_group ON public.transaction(recurrence_group_id);
CREATE INDEX idx_transaction_next_execution ON public.transaction(next_execution_date) 
    WHERE is_recurrent = true;





-- Modificar las restricciones de clave foránea en la tabla transaction
ALTER TABLE public.transaction 
    DROP CONSTRAINT transaction_category_fkey,
    ADD CONSTRAINT transaction_category_fkey 
        FOREIGN KEY (category) 
        REFERENCES public.category(id) 
        ON DELETE SET DEFAULT
        DEFAULT (SELECT id FROM public.category WHERE name = 'UNDEFINED');

ALTER TABLE public.transaction 
    DROP CONSTRAINT transaction_sub_category_fkey,
    ADD CONSTRAINT transaction_sub_category_fkey 
        FOREIGN KEY (sub_category) 
        REFERENCES public.sub_category(id) 
        ON DELETE SET DEFAULT
        DEFAULT (SELECT id FROM public.sub_category WHERE name = 'UNDEFINED');

ALTER TABLE public.transaction 
    DROP CONSTRAINT transaction_transaction_type_fkey,
    ADD CONSTRAINT transaction_transaction_type_fkey 
        FOREIGN KEY (transaction_type) 
        REFERENCES public.transaction_type(id) 
        ON DELETE SET DEFAULT
        DEFAULT (SELECT id FROM public.transaction_type WHERE name = 'UNDEFINED');

ALTER TABLE public.transaction 
    DROP CONSTRAINT transaction_transaction_medium_fkey,
    ADD CONSTRAINT transaction_transaction_medium_fkey 
        FOREIGN KEY (transaction_medium) 
        REFERENCES public.transaction_medium(id) 
        ON DELETE SET DEFAULT
        DEFAULT (SELECT id FROM public.transaction_medium WHERE name = 'UNDEFINED');


-- Crear índices para mejorar el rendimiento de las consultas
CREATE INDEX idx_transaction_history_transaction_id 
    ON public.transaction_history(transaction_id);
CREATE INDEX idx_transaction_history_change_date 
    ON public.transaction_history(change_date);
CREATE INDEX idx_transaction_history_change_type 
    ON public.transaction_history(change_type);
CREATE INDEX idx_transaction_history_user_id 
    ON public.transaction_history(user_id);


-- Índices para mejorar el rendimiento
CREATE INDEX idx_account_transfer_from_account 
    ON public.account_transfer(from_account_id);
CREATE INDEX idx_account_transfer_to_account 
    ON public.account_transfer(to_account_id);
CREATE INDEX idx_account_transfer_date 
    ON public.account_transfer(transfer_date);
CREATE INDEX idx_account_transfer_user 
    ON public.account_transfer(user_id);

-- Enable RLS for all tables
ALTER TABLE public.organization ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budget_jar ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.category ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sub_category ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sub_category_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.period ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.period_income ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.jar_period_budget ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_transfer ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.foreign_currency_transaction ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurrence_group ENABLE ROW LEVEL SECURITY;

-- Create policies for organization
CREATE POLICY "Users can view their own organizations"
    ON public.organization FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own organizations"
    ON public.organization FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own organizations"
    ON public.organization FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own organizations"
    ON public.organization FOR DELETE
    USING (auth.uid() = user_id);

-- Create policies for budget_jar
CREATE POLICY "Users can view their own budget jars"
    ON public.budget_jar FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own budget jars"
    ON public.budget_jar FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own budget jars"
    ON public.budget_jar FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own budget jars"
    ON public.budget_jar FOR DELETE
    USING (auth.uid() = user_id);

-- Create policies for category
CREATE POLICY "Users can view their own categories"
    ON public.category FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own categories"
    ON public.category FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own categories"
    ON public.category FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own categories"
    ON public.category FOR DELETE
    USING (auth.uid() = user_id);

-- Create policies for sub_category
CREATE POLICY "Users can view their own subcategories"
    ON public.sub_category FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own subcategories"
    ON public.sub_category FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own subcategories"
    ON public.sub_category FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own subcategories"
    ON public.sub_category FOR DELETE
    USING (auth.uid() = user_id);

-- Create policies for sub_category_history
CREATE POLICY "Users can view their own subcategory history"
    ON public.sub_category_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own subcategory history"
    ON public.sub_category_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Create policies for account
CREATE POLICY "Users can view their own accounts"
    ON public.account FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own accounts"
    ON public.account FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own accounts"
    ON public.account FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own accounts"
    ON public.account FOR DELETE
    USING (auth.uid() = user_id);

-- Create policies for period
CREATE POLICY "Users can view their own periods"
    ON public.period FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own periods"
    ON public.period FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own periods"
    ON public.period FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own periods"
    ON public.period FOR DELETE
    USING (auth.uid() = user_id);

-- Create policies for period_income
CREATE POLICY "Users can view their own period incomes"
    ON public.period_income FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own period incomes"
    ON public.period_income FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own period incomes"
    ON public.period_income FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own period incomes"
    ON public.period_income FOR DELETE
    USING (auth.uid() = user_id);

-- Create policies for jar_period_budget
CREATE POLICY "Users can view their own jar period budgets"
    ON public.jar_period_budget FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own jar period budgets"
    ON public.jar_period_budget FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own jar period budgets"
    ON public.jar_period_budget FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own jar period budgets"
    ON public.jar_period_budget FOR DELETE
    USING (auth.uid() = user_id);

-- Create policies for transaction
CREATE POLICY "Users can view their own transactions"
    ON public.transaction FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own transactions"
    ON public.transaction FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own transactions"
    ON public.transaction FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own transactions"
    ON public.transaction FOR DELETE
    USING (auth.uid() = user_id);

-- Create policies for transaction_history
CREATE POLICY "Users can view their own transaction history"
    ON public.transaction_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own transaction history"
    ON public.transaction_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Create policies for account_transfer
CREATE POLICY "Users can view their own account transfers"
    ON public.account_transfer FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own account transfers"
    ON public.account_transfer FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Create policies for foreign_currency_transaction
CREATE POLICY "Users can view their own foreign currency transactions"
    ON public.foreign_currency_transaction FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.transaction t 
        WHERE t.id = foreign_currency_transaction.transaction_id 
        AND t.user_id = auth.uid()
    ));

CREATE POLICY "Users can insert their own foreign currency transactions"
    ON public.foreign_currency_transaction FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.transaction t 
        WHERE t.id = foreign_currency_transaction.transaction_id 
        AND t.user_id = auth.uid()
    ));

-- Create policies for recurrence_group
CREATE POLICY "Users can view their own recurrence groups"
    ON public.recurrence_group FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own recurrence groups"
    ON public.recurrence_group FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own recurrence groups"
    ON public.recurrence_group FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own recurrence groups"
    ON public.recurrence_group FOR DELETE
    USING (auth.uid() = user_id);