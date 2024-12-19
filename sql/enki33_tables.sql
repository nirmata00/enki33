-- 1. First, system tables that don't depend on other tables

-- Currency table and related objects
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

ALTER TABLE public.currency ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read access to currency table"
    ON public.currency FOR SELECT
    TO authenticated
    USING (true);

CREATE INDEX idx_currency_active ON public.currency(id) WHERE is_active = true;
CREATE INDEX idx_currency_code ON public.currency(code);

-- Transaction Type table and related objects
CREATE TABLE public.transaction_type (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

ALTER TABLE public.transaction_type ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read access to transaction_type table"
    ON public.transaction_type FOR SELECT
    TO authenticated
    USING (true);

CREATE INDEX idx_transaction_type_active ON public.transaction_type(id) WHERE is_active = true;

-- Transaction Medium table (system table)
CREATE TABLE public.transaction_medium (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

ALTER TABLE public.transaction_medium ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read access to transaction_medium table"
    ON public.transaction_medium FOR SELECT
    TO authenticated
    USING (true);

CREATE INDEX idx_transaction_medium_active ON public.transaction_medium(id) WHERE is_active = true;

-- 2. Then tables that depend on auth.users

-- App User table and related objects
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

ALTER TABLE public.app_user ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile"
    ON public.app_user FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
    ON public.app_user FOR UPDATE
    USING (auth.uid() = id);

CREATE POLICY "Users can insert their own profile"
    ON public.app_user FOR INSERT
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can delete their own profile"
    ON public.app_user FOR DELETE
    USING (auth.uid() = id);

CREATE INDEX idx_app_user_email ON public.app_user(email);
CREATE INDEX idx_app_user_active ON public.app_user(id) WHERE is_active = true;

-- 3. Then tables that depend on app_user

-- Organization table and related objects
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

ALTER TABLE public.organization ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_organization_user ON public.organization(user_id);
CREATE INDEX idx_organization_code ON public.organization(code);
CREATE INDEX idx_active_organizations ON public.organization(id) WHERE is_active = true;

-- ... continue with other tables in proper dependency order


-- Budget Jar table and related objects
CREATE TABLE public.budget_jar (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    percentage numeric(5,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT check_percentage CHECK (percentage >= 0 AND percentage <= 100),
    CONSTRAINT check_total_percentage CHECK (
        (SELECT COALESCE(SUM(percentage), 0)
         FROM public.budget_jar bj2
         WHERE bj2.user_id = user_id) <= 100
    )
);

ALTER TABLE public.budget_jar ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_budget_jar_user ON public.budget_jar(user_id) WHERE is_active = true;

-- Category table and related objects
CREATE TABLE public.category (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE
);

ALTER TABLE public.category ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_category_user ON public.category(user_id);
CREATE INDEX idx_category_active ON public.category(id) WHERE is_active = true;

-- Sub Category table and related objects
CREATE TABLE public.sub_category (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    category_id uuid NOT NULL DEFAULT (SELECT id FROM public.category WHERE name = 'UNDEFINED')
        REFERENCES public.category(id) ON DELETE SET DEFAULT,
    budget_jar_id uuid NOT NULL DEFAULT (SELECT id FROM public.budget_jar WHERE name = 'UNDEFINED')
        REFERENCES public.budget_jar(id) ON DELETE SET DEFAULT,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE
);

ALTER TABLE public.sub_category ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_sub_category_user ON public.sub_category(user_id);
CREATE INDEX idx_sub_category_category ON public.sub_category(category_id);
CREATE INDEX idx_sub_category_budget_jar ON public.sub_category(budget_jar_id);
CREATE INDEX idx_sub_category_active ON public.sub_category(id) WHERE is_active = true;

-- Sub Category History table and related objects
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
);

ALTER TABLE public.sub_category_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own subcategory history"
    ON public.sub_category_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own subcategory history"
    ON public.sub_category_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own subcategory history"
    ON public.sub_category_history FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own subcategory history"
    ON public.sub_category_history FOR DELETE
    USING (auth.uid() = user_id);

CREATE INDEX idx_sub_category_history_subcategory ON public.sub_category_history(sub_category_id);
CREATE INDEX idx_sub_category_history_user ON public.sub_category_history(user_id);
CREATE INDEX idx_sub_category_history_date ON public.sub_category_history(change_date);
CREATE INDEX idx_sub_category_history_change_type ON public.sub_category_history(change_type);


-- Account table and related objects
CREATE TABLE public.account (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    initial_balance numeric(15,2) NOT NULL DEFAULT 0,
    currency_id uuid NOT NULL DEFAULT (SELECT id FROM public.currency WHERE code = 'UND') 
        REFERENCES public.currency(id) ON DELETE SET DEFAULT,
    is_active boolean NOT NULL DEFAULT true,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

ALTER TABLE public.account ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_account_user ON public.account(user_id);
CREATE INDEX idx_account_currency ON public.account(currency_id);
CREATE INDEX idx_active_accounts ON public.account(id) WHERE is_active = true;

-- Period table and related objects
CREATE TABLE public.period (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    start_date date NOT NULL,
    end_date date NOT NULL,
    name text NOT NULL,
    is_closed boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT check_period_dates CHECK (end_date >= start_date)
);

ALTER TABLE public.period ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_period_user ON public.period(user_id);
CREATE INDEX idx_period_dates ON public.period(start_date, end_date);
CREATE INDEX idx_active_periods ON public.period(id) WHERE is_active = true;

-- Period Income table and related objects
CREATE TABLE public.period_income (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    period_id uuid NOT NULL REFERENCES public.period(id) ON DELETE CASCADE,
    total_income numeric(15,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT unique_period_income UNIQUE (period_id),
    CONSTRAINT check_income_positive CHECK (total_income >= 0)
);

ALTER TABLE public.period_income ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_period_income_user ON public.period_income(user_id);
CREATE INDEX idx_period_income_period ON public.period_income(period_id);

-- Jar Period Budget table and related objects
CREATE TABLE public.jar_period_budget (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    period_id uuid NOT NULL REFERENCES public.period(id) ON DELETE CASCADE,
    budget_jar_id uuid NOT NULL REFERENCES public.budget_jar(id) ON DELETE CASCADE,
    calculated_amount numeric(15,2) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    is_active boolean NOT NULL DEFAULT true,
    CONSTRAINT unique_jar_period UNIQUE (period_id, budget_jar_id),
    CONSTRAINT check_amount_positive CHECK (calculated_amount >= 0)
);

ALTER TABLE public.jar_period_budget ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_jar_period_budget_user ON public.jar_period_budget(user_id);
CREATE INDEX idx_jar_period_budget_period ON public.jar_period_budget(period_id);
CREATE INDEX idx_jar_period_budget_jar ON public.jar_period_budget(budget_jar_id);

-- Recurrence Frequency table (system table)
CREATE TABLE public.recurrence_frequency (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text NOT NULL,
    description text,
    interval_value interval NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz
);

ALTER TABLE public.recurrence_frequency ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read access to recurrence_frequency table"
    ON public.recurrence_frequency FOR SELECT
    TO authenticated
    USING (true);

CREATE INDEX idx_recurrence_frequency_active ON public.recurrence_frequency(id) WHERE is_active = true;



-- Recurrent Transaction Template table
CREATE TABLE public.recurrent_transaction_template (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    description text,
    scheduled_amount numeric(15, 2) NOT NULL,
    currency_id uuid NOT NULL DEFAULT (SELECT id FROM public.currency WHERE code = 'UND')
        REFERENCES public.currency(id) ON DELETE SET DEFAULT,
    organization_id uuid NOT NULL DEFAULT (SELECT id FROM public.organization WHERE code = 'UND')
        REFERENCES public.organization(id) ON DELETE SET DEFAULT,
    category_id uuid NOT NULL DEFAULT (SELECT id FROM public.category WHERE name = 'UNDEFINED')
        REFERENCES public.category(id) ON DELETE SET DEFAULT,
    sub_category_id uuid NOT NULL DEFAULT (SELECT id FROM public.sub_category WHERE name = 'UNDEFINED')
        REFERENCES public.sub_category(id) ON DELETE SET DEFAULT,
    account_id uuid NOT NULL REFERENCES public.account(id),
    transaction_type_id uuid NOT NULL DEFAULT (SELECT id FROM public.transaction_type WHERE name = 'UNDEFINED')
        REFERENCES public.transaction_type(id) ON DELETE SET DEFAULT,
    transaction_medium_id uuid DEFAULT (SELECT id FROM public.transaction_medium WHERE name = 'UNDEFINED')
        REFERENCES public.transaction_medium(id) ON DELETE SET DEFAULT,
    is_expense boolean NOT NULL DEFAULT true,
    frequency_id uuid NOT NULL REFERENCES public.recurrence_frequency(id),
    execution_day smallint,
    cut_day smallint,
    payment_day smallint,
    start_date date NOT NULL,
    end_date date,
    next_execution_date date NOT NULL,
    status varchar(20) NOT NULL DEFAULT 'ACTIVE' 
        CHECK (status IN ('ACTIVE', 'PAUSED', 'CANCELLED')),
    execution_count integer DEFAULT 0,
    max_executions integer,
    last_execution_at timestamptz,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    modified_at timestamptz,
    CONSTRAINT check_scheduled_amount_not_zero CHECK (scheduled_amount != 0),
    CONSTRAINT check_execution_day CHECK (execution_day BETWEEN 1 AND 31),
    CONSTRAINT check_cut_day CHECK (cut_day BETWEEN 1 AND 31),
    CONSTRAINT check_payment_day CHECK (payment_day BETWEEN 1 AND 31)
);

ALTER TABLE public.recurrent_transaction_template ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own recurrent transaction templates"
    ON public.recurrent_transaction_template FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own recurrent transaction templates"
    ON public.recurrent_transaction_template FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own recurrent transaction templates"
    ON public.recurrent_transaction_template FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own recurrent transaction templates"
    ON public.recurrent_transaction_template FOR DELETE
    USING (auth.uid() = user_id);

CREATE INDEX idx_template_user ON public.recurrent_transaction_template(user_id);
CREATE INDEX idx_template_next_execution ON public.recurrent_transaction_template(next_execution_date);
CREATE INDEX idx_template_status ON public.recurrent_transaction_template(status);
CREATE INDEX idx_active_templates ON public.recurrent_transaction_template(next_execution_date) 
    WHERE status = 'ACTIVE';

-- Transaction table
CREATE TABLE public.transaction (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    registered_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    date date NOT NULL,
    amount numeric(15, 2) NOT NULL,
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
    template_id uuid REFERENCES public.recurrent_transaction_template(id),
    CONSTRAINT check_amount_not_zero CHECK (amount != 0),
    CONSTRAINT check_transaction_date CHECK (date <= CURRENT_DATE)
);

ALTER TABLE public.transaction ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_transaction_user ON public.transaction(user_id);
CREATE INDEX idx_transaction_date ON public.transaction(date);
CREATE INDEX idx_transaction_account ON public.transaction(account);
CREATE INDEX idx_transaction_category ON public.transaction(category);
CREATE INDEX idx_transaction_sub_category ON public.transaction(sub_category);
CREATE INDEX idx_transaction_template ON public.transaction(template_id);
CREATE INDEX idx_transaction_organization ON public.transaction(organization_id);
CREATE INDEX idx_expense_transactions ON public.transaction(date, amount) WHERE is_expense = true;

-- Recurrence Execution table
CREATE TABLE public.recurrence_execution (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    transaction_id uuid NOT NULL REFERENCES public.transaction(id) ON DELETE CASCADE,
    template_id uuid NOT NULL REFERENCES public.recurrent_transaction_template(id),
    execution_number integer NOT NULL,
    scheduled_amount numeric(15, 2) NOT NULL,
    actual_amount numeric(15, 2) NOT NULL,
    amount_variation numeric(15, 2) GENERATED ALWAYS AS (
        actual_amount - scheduled_amount
    ) STORED,
    execution_date date NOT NULL,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_amounts_not_zero CHECK (
        scheduled_amount != 0 AND actual_amount != 0
    ),
    CONSTRAINT unique_template_execution UNIQUE (template_id, execution_number)
);

ALTER TABLE public.recurrence_execution ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own recurrence executions"
    ON public.recurrence_execution FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own recurrence executions"
    ON public.recurrence_execution FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE INDEX idx_recurrence_execution_template ON public.recurrence_execution(template_id);
CREATE INDEX idx_recurrence_execution_transaction ON public.recurrence_execution(transaction_id);
CREATE INDEX idx_recurrence_execution_date ON public.recurrence_execution(execution_date);
CREATE INDEX idx_recurrence_execution_user ON public.recurrence_execution(user_id);

-- Account Transfer table
CREATE TABLE public.account_transfer (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    amount numeric(15,2) NOT NULL,
    from_account_id uuid NOT NULL DEFAULT (SELECT id FROM public.account WHERE name = 'UNDEFINED')
        REFERENCES public.account(id) ON DELETE SET DEFAULT,
    to_account_id uuid NOT NULL DEFAULT (SELECT id FROM public.account WHERE name = 'UNDEFINED')
        REFERENCES public.account(id) ON DELETE SET DEFAULT,
    transaction_id uuid NOT NULL REFERENCES public.transaction(id) ON DELETE CASCADE,
    transfer_date date NOT NULL,
    exchange_rate numeric(20,6) DEFAULT 1.0,
    notes text,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT different_accounts CHECK (from_account_id != to_account_id),
    CONSTRAINT check_transfer_amount CHECK (amount > 0),
    CONSTRAINT check_exchange_rate CHECK (exchange_rate > 0)
);

ALTER TABLE public.account_transfer ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own account transfers"
    ON public.account_transfer FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own account transfers"
    ON public.account_transfer FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE INDEX idx_account_transfer_from ON public.account_transfer(from_account_id);
CREATE INDEX idx_account_transfer_to ON public.account_transfer(to_account_id);
CREATE INDEX idx_account_transfer_transaction ON public.account_transfer(transaction_id);
CREATE INDEX idx_account_transfer_date ON public.account_transfer(transfer_date);
CREATE INDEX idx_account_transfer_user ON public.account_transfer(user_id);

-- Account Transfer History table
CREATE TABLE public.account_transfer_history (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    transfer_id uuid NOT NULL REFERENCES public.account_transfer(id) ON DELETE CASCADE,
    change_date timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    change_type varchar(20) NOT NULL CHECK (
        change_type IN ('FROM_ACCOUNT', 'TO_ACCOUNT', 'BOTH')
    ),
    old_from_account_id uuid REFERENCES public.account(id) ON DELETE SET NULL,
    new_from_account_id uuid REFERENCES public.account(id) ON DELETE SET NULL,
    old_to_account_id uuid REFERENCES public.account(id) ON DELETE SET NULL,
    new_to_account_id uuid REFERENCES public.account(id) ON DELETE SET NULL,
    user_id uuid NOT NULL REFERENCES public.app_user(id) ON DELETE CASCADE,
    notes text
);

ALTER TABLE public.account_transfer_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own transfer history"
    ON public.account_transfer_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own transfer history"
    ON public.account_transfer_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE INDEX idx_account_transfer_history_transfer ON public.account_transfer_history(transfer_id);
CREATE INDEX idx_account_transfer_history_date ON public.account_transfer_history(change_date);
CREATE INDEX idx_account_transfer_history_user ON public.account_transfer_history(user_id);

-- Foreign Currency Transaction table
CREATE TABLE public.foreign_currency_transaction (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    transaction_id uuid NOT NULL REFERENCES public.transaction(id) ON DELETE CASCADE,
    original_amount numeric(15,2) NOT NULL,
    original_currency_id uuid NOT NULL DEFAULT (SELECT id FROM public.currency WHERE code = 'UND')
        REFERENCES public.currency(id) ON DELETE SET DEFAULT,
    exchange_rate numeric(20,6) NOT NULL,
    transaction_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_exchange_rate_positive CHECK (exchange_rate > 0),
    CONSTRAINT check_original_amount_not_zero CHECK (original_amount != 0)
);

ALTER TABLE public.foreign_currency_transaction ENABLE ROW LEVEL SECURITY;

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

CREATE INDEX idx_foreign_currency_transaction_transaction ON public.foreign_currency_transaction(transaction_id);
CREATE INDEX idx_foreign_currency_transaction_currency ON public.foreign_currency_transaction(original_currency_id);
CREATE INDEX idx_foreign_currency_transaction_date ON public.foreign_currency_transaction(transaction_date);

-- Create function to update modified_at timestamp
CREATE OR REPLACE FUNCTION update_modified_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.modified_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to all tables with modified_at column
CREATE TRIGGER update_app_user_modtime
    BEFORE UPDATE ON public.app_user
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at_column();

CREATE TRIGGER update_organization_modtime
    BEFORE UPDATE ON public.organization
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at_column();

CREATE TRIGGER update_currency_modtime
    BEFORE UPDATE ON public.currency
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at_column();

CREATE TRIGGER update_budget_jar_modtime
    BEFORE UPDATE ON public.budget_jar
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at_column();

CREATE TRIGGER update_category_modtime
    BEFORE UPDATE ON public.category
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at_column();

CREATE TRIGGER update_sub_category_modtime
    BEFORE UPDATE ON public.sub_category
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at_column();

CREATE TRIGGER update_account_modtime
    BEFORE UPDATE ON public.account
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at_column();

CREATE TRIGGER update_period_income_modtime
    BEFORE UPDATE ON public.period_income
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at_column();

CREATE TRIGGER update_recurrent_transaction_template_modtime
    BEFORE UPDATE ON public.recurrent_transaction_template
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_at_column();


