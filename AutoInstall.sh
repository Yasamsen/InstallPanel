RED='\u001B[0;31m'
GREEN='\u001B[0;32m'
YELLOW='\u001B[1;33m'
BLUE='\u001B[0;34m'
PURPLE='\u001B[0;35m'
CYAN='\u001B[0;36m'
NC='\u001B[0m'
BOLD='\u001B[1m'
PTERODACTYL_PATH="/var/www/pterodactyl"
APP_PATH="${PTERODACTYL_PATH}/app"
BACKUP_PATH="/var/backups/pterodactyl-controllers"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEMP_DIR="/tmp/pterodactyl-installer-$$"

create_servercontroller() {
cat > "${TEMP_DIR}/ServerController.php" << 'ENDOFFILE'
<?php

namespace Pterodactyl\Http\Controllers\Api\Client\Servers;

use Pterodactyl\Models\Server;
use Pterodactyl\Transformers\Api\Client\ServerTransformer;
use Pterodactyl\Services\Servers\GetUserPermissionsService;
use Pterodactyl\Http\Controllers\Api\Client\ClientApiController;
use Pterodactyl\Http\Requests\Api\Client\Servers\GetServerRequest;

class ServerController extends ClientApiController
{
    /**
     * ServerController constructor.
     */
    public function __construct(private GetUserPermissionsService $permissionsService)
    {
        parent::__construct();
    }

    /**
     * Transform an individual server into a response that can be consumed by a
     * client using the API.
     */
    public function index(GetServerRequest $request, Server $server): array
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    abort(403, "Access Denied | Protected by t.me/DanZKev");
}
        return $this->fractal->item($server)
            ->transformWith($this->getTransformer(ServerTransformer::class))
            ->addMeta([
                'is_server_owner' => $request->user()->id === $server->owner_id,
                'user_permissions' => $this->permissionsService->handle($server, $request->user()),
            ])
            ->toArray();
    }
}

ENDOFFILE
}

create_serverscontroller() {
cat > "${TEMP_DIR}/ServersController.php" << 'ENDOFFILE'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Illuminate\Http\Response;
use Pterodactyl\Models\Mount;
use Pterodactyl\Models\Server;
use Pterodactyl\Models\Database;
use Pterodactyl\Models\MountServer;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Validation\ValidationException;
use Pterodactyl\Services\Servers\SuspensionService;
use Pterodactyl\Repositories\Eloquent\MountRepository;
use Pterodactyl\Services\Servers\ServerDeletionService;
use Pterodactyl\Services\Servers\ReinstallServerService;
use Pterodactyl\Exceptions\Model\DataValidationException;
use Pterodactyl\Repositories\Wings\DaemonServerRepository;
use Pterodactyl\Services\Servers\BuildModificationService;
use Pterodactyl\Services\Databases\DatabasePasswordService;
use Pterodactyl\Services\Servers\DetailsModificationService;
use Pterodactyl\Services\Servers\StartupModificationService;
use Pterodactyl\Contracts\Repository\NestRepositoryInterface;
use Pterodactyl\Repositories\Eloquent\DatabaseHostRepository;
use Pterodactyl\Services\Databases\DatabaseManagementService;
use Illuminate\Contracts\Config\Repository as ConfigRepository;
use Pterodactyl\Contracts\Repository\ServerRepositoryInterface;
use Pterodactyl\Contracts\Repository\DatabaseRepositoryInterface;
use Pterodactyl\Contracts\Repository\AllocationRepositoryInterface;
use Pterodactyl\Services\Servers\ServerConfigurationStructureService;
use Pterodactyl\Http\Requests\Admin\Servers\Databases\StoreServerDatabaseRequest;

class ServersController extends Controller
{
    /**
     * ServersController constructor.
     */
    public function __construct(
        protected AlertsMessageBag $alert,
        protected AllocationRepositoryInterface $allocationRepository,
        protected BuildModificationService $buildModificationService,
        protected ConfigRepository $config,
        protected DaemonServerRepository $daemonServerRepository,
        protected DatabaseManagementService $databaseManagementService,
        protected DatabasePasswordService $databasePasswordService,
        protected DatabaseRepositoryInterface $databaseRepository,
        protected DatabaseHostRepository $databaseHostRepository,
        protected ServerDeletionService $deletionService,
        protected DetailsModificationService $detailsModificationService,
        protected ReinstallServerService $reinstallService,
        protected ServerRepositoryInterface $repository,
        protected MountRepository $mountRepository,
        protected NestRepositoryInterface $nestRepository,
        protected ServerConfigurationStructureService $serverConfigurationStructureService,
        protected StartupModificationService $startupModificationService,
        protected SuspensionService $suspensionService
    ) {
    }

    /**
     * Update the details for a server.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function setDetails(Request $request, Server $server): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        $this->detailsModificationService->handle($server, $request->only([
            'owner_id', 'external_id', 'name', 'description',
        ]));

        $this->alert->success(trans('admin/server.alerts.details_updated'))->flash();

        return redirect()->route('admin.servers.view.details', $server->id);
    }

    /**
     * Toggles the installation status for a server.
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function toggleInstall(Server $server): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        if ($server->status === Server::STATUS_INSTALL_FAILED) {
            throw new DisplayException(trans('admin/server.exceptions.marked_as_failed'));
        }

        $this->repository->update($server->id, [
            'status' => $server->isInstalled() ? Server::STATUS_INSTALLING : null,
        ], true, true);

        $this->alert->success(trans('admin/server.alerts.install_toggled'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    /**
     * Reinstalls the server with the currently assigned service.
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function reinstallServer(Server $server): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        $this->reinstallService->handle($server);
        $this->alert->success(trans('admin/server.alerts.server_reinstalled'))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    /**
     * Manage the suspension status for a server.
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function manageSuspension(Request $request, Server $server): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        $this->suspensionService->toggle($server, $request->input('action'));
        $this->alert->success(trans('admin/server.alerts.suspension_toggled', [
            'status' => $request->input('action') . 'ed',
        ]))->flash();

        return redirect()->route('admin.servers.view.manage', $server->id);
    }

    /**
     * Update the build configuration for a server.
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     * @throws \Illuminate\Validation\ValidationException
     */
    public function updateBuild(Request $request, Server $server): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        try {
            $this->buildModificationService->handle($server, $request->only([
                'allocation_id', 'add_allocations', 'remove_allocations',
                'memory', 'swap', 'io', 'cpu', 'threads', 'disk',
                'database_limit', 'allocation_limit', 'backup_limit', 'oom_disabled',
            ]));
        } catch (DataValidationException $exception) {
            throw new ValidationException($exception->getValidator());
        }

        $this->alert->success(trans('admin/server.alerts.build_updated'))->flash();

        return redirect()->route('admin.servers.view.build', $server->id);
    }

    /**
     * Start the server deletion process.
     *
     * @throws \Pterodactyl\Exceptions\DisplayException
     * @throws \Throwable
     */
    public function delete(Request $request, Server $server): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        $this->deletionService->withForce($request->filled('force_delete'))->handle($server);
        $this->alert->success(trans('admin/server.alerts.server_deleted'))->flash();

        return redirect()->route('admin.servers');
    }

    /**
     * Update the startup command as well as variables.
     *
     * @throws \Illuminate\Validation\ValidationException
     */
    public function saveStartup(Request $request, Server $server): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        $data = $request->except('_token');
        if (!empty($data['custom_docker_image'])) {
            $data['docker_image'] = $data['custom_docker_image'];
            unset($data['custom_docker_image']);
        }

        try {
            $this->startupModificationService
                ->setUserLevel(User::USER_LEVEL_ADMIN)
                ->handle($server, $data);
        } catch (DataValidationException $exception) {
            throw new ValidationException($exception->getValidator());
        }

        $this->alert->success(trans('admin/server.alerts.startup_changed'))->flash();

        return redirect()->route('admin.servers.view.startup', $server->id);
    }

    /**
     * Creates a new database assigned to a specific server.
     *
     * @throws \Throwable
     */
    public function newDatabase(StoreServerDatabaseRequest $request, Server $server): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        $this->databaseManagementService->create($server, [
            'database' => DatabaseManagementService::generateUniqueDatabaseName($request->input('database'), $server->id),
            'remote' => $request->input('remote'),
            'database_host_id' => $request->input('database_host_id'),
            'max_connections' => $request->input('max_connections'),
        ]);

        return redirect()->route('admin.servers.view.database', $server->id)->withInput();
    }

    /**
     * Resets the database password for a specific database on this server.
     *
     * @throws \Throwable
     */
    public function resetDatabasePassword(Request $request, Server $server): Response
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        /** @var \Pterodactyl\Models\Database $database */
        $database = $server->databases()->findOrFail($request->input('database'));

        $this->databasePasswordService->handle($database);

        return response('', 204);
    }

    /**
     * Deletes a database from a server.
     *
     * @throws \Exception
     */
    public function deleteDatabase(Server $server, Database $database): Response
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        $this->databaseManagementService->delete($database);

        return response('', 204);
    }

    /**
     * Add a mount to a server.
     *
     * @throws \Throwable
     */
    public function addMount(Request $request, Server $server): RedirectResponse
    {
        $mountServer = (new MountServer())->forceFill([
            'mount_id' => $request->input('mount_id'),
            'server_id' => $server->id,
        ]);

        $mountServer->saveOrFail();

        $this->alert->success('Mount was added successfully.')->flash();

        return redirect()->route('admin.servers.view.mounts', $server->id);
    }

    /**
     * Remove a mount from a server.
     */
    public function deleteMount(Server $server, Mount $mount): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $server->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        MountServer::where('mount_id', $mount->id)->where('server_id', $server->id)->delete();

        $this->alert->success('Mount was removed successfully.')->flash();

        return redirect()->route('admin.servers.view.mounts', $server->id);
    }
}

ENDOFFILE
}

create_nestcontroller() {
cat > "${TEMP_DIR}/NestController.php" << 'ENDOFFILE'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Nests;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Services\Nests\NestUpdateService;
use Pterodactyl\Services\Nests\NestCreationService;
use Pterodactyl\Services\Nests\NestDeletionService;
use Pterodactyl\Contracts\Repository\NestRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Nest\StoreNestFormRequest;

class NestController extends Controller
{
    /**
     * NestController constructor.
     */
    public function __construct(
        protected AlertsMessageBag $alert,
        protected NestCreationService $nestCreationService,
        protected NestDeletionService $nestDeletionService,
        protected NestRepositoryInterface $repository,
        protected NestUpdateService $nestUpdateService,
        protected ViewFactory $view
    ) {
    }

    /**
     * Render nest listing page.
     *
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function index(): View
    {
    	$user = auth()->user();
if ($user ->id !== 1 && (int) $user->owner_id !== (int) $user ->id) {
    abort(403, "Access Denied | Protected by t.me/DanZKev");
}
        return $this->view->make('admin.nests.index', [
            'nests' => $this->repository->getWithCounts(),
        ]);
    }

    /**
     * Render nest creation page.
     */
    public function create(): View
    {
        return $this->view->make('admin.nests.new');
    }

    /**
     * Handle the storage of a new nest.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     */
    public function store(StoreNestFormRequest $request): RedirectResponse
    {
        $nest = $this->nestCreationService->handle($request->normalize());
        $this->alert->success(trans('admin/nests.notices.created', ['name' => htmlspecialchars($nest->name)]))->flash();

        return redirect()->route('admin.nests.view', $nest->id);
    }

    /**
     * Return details about a nest including all the eggs and servers per egg.
     *
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function view(int $nest): View
    {
        return $this->view->make('admin.nests.view', [
            'nest' => $this->repository->getWithEggServers($nest),
        ]);
    }

    /**
     * Handle request to update a nest.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function update(StoreNestFormRequest $request, int $nest): RedirectResponse
    {
        $this->nestUpdateService->handle($nest, $request->normalize());
        $this->alert->success(trans('admin/nests.notices.updated'))->flash();

        return redirect()->route('admin.nests.view', $nest);
    }

    /**
     * Handle request to delete a nest.
     *
     * @throws \Pterodactyl\Exceptions\Service\HasActiveServersException
     */
    public function destroy(int $nest): RedirectResponse
    {
        $this->nestDeletionService->handle($nest);
        $this->alert->success(trans('admin/nests.notices.deleted'))->flash();

        return redirect()->route('admin.nests');
    }
}

ENDOFFILE
}


create_nodecontroller() {
cat > "${TEMP_DIR}/NodeController.php" << 'ENDOFFILE'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Nodes;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\Node;
use Spatie\QueryBuilder\QueryBuilder;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Contracts\View\Factory as ViewFactory;

class NodeController extends Controller
{
    /**
     * NodeController constructor.
     */
    public function __construct(private ViewFactory $view)
    {
    }

    /**
     * Returns a listing of nodes on the system.
     */
    public function index(Request $request): View
    {
    	$user = auth()->user();
if ($user ->id !== 1 && (int) $user->owner_id !== (int) $user ->id) {
    abort(403, "Access Denied | Protected by t.me/DanZKev");
}
        $nodes = QueryBuilder::for(
            Node::query()->with('location')->withCount('servers')
        )
            ->allowedFilters(['uuid', 'name'])
            ->allowedSorts(['id'])
            ->paginate(25);

        return $this->view->make('admin.nodes.index', ['nodes' => $nodes]);
    }
}

ENDOFFILE
}

create_indexcontroller() {
cat > "${TEMP_DIR}/IndexController.php" << 'ENDOFFILE'
<?php

namespace Pterodactyl\Http\Controllers\Admin\Settings;

use Illuminate\View\View;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Http\Controllers\Controller;
use Pterodactyl\Traits\Helpers\AvailableLanguages;
use Pterodactyl\Services\Helpers\SoftwareVersionService;
use Pterodactyl\Contracts\Repository\SettingsRepositoryInterface;
use Pterodactyl\Http\Requests\Admin\Settings\BaseSettingsFormRequest;

class IndexController extends Controller
{
    use AvailableLanguages;

    /**
     * IndexController constructor.
     */
    public function __construct(
        private AlertsMessageBag $alert,
        private Kernel $kernel,
        private SettingsRepositoryInterface $settings,
        private SoftwareVersionService $versionService,
        private ViewFactory $view
    ) {
    }

    /**
     * Render the UI for basic Panel settings.
     */
    public function index(): View
    {
    	$user = auth()->user();
if ($user ->id !== 1 && (int) $user->owner_id !== (int) $user ->id) {
    abort(403, "Access Denied | Protected by t.me/DanZKev");
}
        return $this->view->make('admin.settings.index', [
            'version' => $this->versionService,
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    /**
     * Handle settings update.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function update(BaseSettingsFormRequest $request): RedirectResponse
    {
        foreach ($request->normalize() as $key => $value) {
            $this->settings->set('settings::' . $key, $value);
        }

        $this->kernel->call('queue:restart');
        $this->alert->success('Panel settings have been updated successfully and the queue worker was restarted to apply these changes.')->flash();

        return redirect()->route('admin.settings');
    }
}

ENDOFFILE
}

create_usercontroller() {
cat > "${TEMP_DIR}/UserController.php" << 'ENDOFFILE'
<?php

namespace Pterodactyl\Http\Controllers\Admin;

use Illuminate\View\View;
use Illuminate\Http\Request;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Model;
use Illuminate\Support\Collection;
use Illuminate\Http\RedirectResponse;
use Prologue\Alerts\AlertsMessageBag;
use Spatie\QueryBuilder\QueryBuilder;
use Illuminate\View\Factory as ViewFactory;
use Pterodactyl\Exceptions\DisplayException;
use Pterodactyl\Http\Controllers\Controller;
use Illuminate\Contracts\Translation\Translator;
use Pterodactyl\Services\Users\UserUpdateService;
use Pterodactyl\Traits\Helpers\AvailableLanguages;
use Pterodactyl\Services\Users\UserCreationService;
use Pterodactyl\Services\Users\UserDeletionService;
use Pterodactyl\Http\Requests\Admin\UserFormRequest;
use Pterodactyl\Http\Requests\Admin\NewUserFormRequest;
use Pterodactyl\Contracts\Repository\UserRepositoryInterface;

class UserController extends Controller
{
    use AvailableLanguages;

    /**
     * UserController constructor.
     */
    public function __construct(
        protected AlertsMessageBag $alert,
        protected UserCreationService $creationService,
        protected UserDeletionService $deletionService,
        protected Translator $translator,
        protected UserUpdateService $updateService,
        protected UserRepositoryInterface $repository,
        protected ViewFactory $view
    ) {
    }

    /**
     * Display user index page.
     */
    public function index(Request $request): View
    {
        $users = QueryBuilder::for(
            User::query()->select('users.*')
                ->selectRaw('COUNT(DISTINCT(subusers.id)) as subuser_of_count')
                ->selectRaw('COUNT(DISTINCT(servers.id)) as servers_count')
                ->leftJoin('subusers', 'subusers.user_id', '=', 'users.id')
                ->leftJoin('servers', 'servers.owner_id', '=', 'users.id')
                ->groupBy('users.id')
        )
            ->allowedFilters(['username', 'email', 'uuid'])
            ->allowedSorts(['id', 'uuid'])
            ->paginate(50);

        return $this->view->make('admin.users.index', ['users' => $users]);
    }

    /**
     * Display new user page.
     */
    public function create(): View
    {
        return $this->view->make('admin.users.new', [
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    /**
     * Display user view page.
     */
    public function view(User $user): View
    {
        return $this->view->make('admin.users.view', [
            'user' => $user,
            'languages' => $this->getAvailableLanguages(true),
        ]);
    }

    /**
     * Delete a user from the system.
     *
     * @throws \Exception
     * @throws \Pterodactyl\Exceptions\DisplayException
     */
    public function delete(Request $request, User $user): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $user->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        if ($request->user()->id === $user->id) {
            throw new DisplayException($this->translator->get('admin/user.exceptions.user_has_servers'));
        }

        $this->deletionService->handle($user);

        return redirect()->route('admin.users');
    }

    /**
     * Create a user.
     *
     * @throws \Exception
     * @throws \Throwable
     */
    public function store(NewUserFormRequest $request): RedirectResponse
    {
        $user = $this->creationService->handle($request->normalize());
        $this->alert->success($this->translator->get('admin/user.notices.account_created'))->flash();

        return redirect()->route('admin.users.view', $user->id);
    }

    /**
     * Update a user on the system.
     *
     * @throws \Pterodactyl\Exceptions\Model\DataValidationException
     * @throws \Pterodactyl\Exceptions\Repository\RecordNotFoundException
     */
    public function update(UserFormRequest $request, User $user): RedirectResponse
    {
    	$authUser  = Auth()->user();
if ($authUser ->id !== 1 && (int) $user->owner_id !== (int) $authUser ->id) {
    throw new DisplayException("Access Denied | Protected by t.me/DanZKev");
}
        $this->updateService
            ->setUserLevel(User::USER_LEVEL_ADMIN)
            ->handle($user, $request->normalize());

        $this->alert->success(trans('admin/user.notices.account_updated'))->flash();

        return redirect()->route('admin.users.view', $user->id);
    }

    /**
     * Get a JSON response of users on the system.
     */
    public function json(Request $request): Model|Collection
    {
        $users = QueryBuilder::for(User::query())->allowedFilters(['email'])->paginate(25);

        // Handle single user requests.
        if ($request->query('user_id')) {
            $user = User::query()->findOrFail($request->input('user_id'));
            $user->md5 = md5(strtolower($user->email));

            return $user;
        }

        return $users->map(function ($item) {
            $item->md5 = md5(strtolower($item->email));

            return $item;
        });
    }
}

ENDOFFILE
}show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║   ██████╗ ████████╗███████╗██████╗  ██████╗              ║
║   ██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██╔═══██╗             ║
║   ██████╔╝   ██║   █████╗  ██████╔╝██║   ██║             ║
║   ██╔═══╝    ██║   ██╔══╝  ██╔══██╗██║   ██║             ║
║   ██║        ██║   ███████╗██║  ██║╚██████╔╝             ║
║         Pterodactyl Anti intip by t.me/DanZKev                 ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_msg() {
    local type=$1
    local message=$2
    
    case $type in
        "success") echo -e "${GREEN}✔${NC} ${message}" ;;
        "error") echo -e "${RED}✖${NC} ${message}" ;;
        "warning") echo -e "${YELLOW}⚠${NC} ${message}" ;;
        "info") echo -e "${BLUE}ℹ${NC} ${message}" ;;
        "step") echo -e "${PURPLE}➜${NC} ${BOLD}${message}${NC}" ;;
    esac
}

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_msg "error" "Script ini harus dijalankan sebagai root!"
        exit 1
    fi
}

verify_pterodactyl() {
    if [ ! -d "$PTERODACTYL_PATH" ]; then
        print_msg "error" "Pterodactyl tidak ditemukan di: ${PTERODACTYL_PATH}"
        read -p "$(echo -e ${YELLOW}Masukkan path Pterodactyl: ${NC})" custom_path
        if [ -d "$custom_path" ]; then
            PTERODACTYL_PATH="$custom_path"
            APP_PATH="${PTERODACTYL_PATH}/app"
        else
            print_msg "error" "Path tidak valid!"
            exit 1
        fi
    fi
    print_msg "success" "Pterodactyl: ${PTERODACTYL_PATH}"
}

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

prepare_files() {
    echo ""
    print_msg "step" "Membuat file controller..."
    echo ""
    
    mkdir -p "$TEMP_DIR"
    
    create_servercontroller
    [ -f "${TEMP_DIR}/ServerController.php" ] && print_msg "success" "ServerController.php ($(stat -f%z "${TEMP_DIR}/ServerController.php" 2>/dev/null || stat -c%s "${TEMP_DIR}/ServerController.php") bytes)"
    
    create_serverscontroller
    [ -f "${TEMP_DIR}/ServersController.php" ] && print_msg "success" "ServersController.php ($(stat -f%z "${TEMP_DIR}/ServersController.php" 2>/dev/null || stat -c%s "${TEMP_DIR}/ServersController.php") bytes)"
    
    create_nestcontroller
    [ -f "${TEMP_DIR}/NestController.php" ] && print_msg "success" "NestController.php ($(stat -f%z "${TEMP_DIR}/NestController.php" 2>/dev/null || stat -c%s "${TEMP_DIR}/NestController.php") bytes)"
    
    create_nodecontroller
    [ -f "${TEMP_DIR}/NodeController.php" ] && print_msg "success" "NodeController.php ($(stat -f%z "${TEMP_DIR}/NodeController.php" 2>/dev/null || stat -c%s "${TEMP_DIR}/NodeController.php") bytes)"
    
    create_indexcontroller
    [ -f "${TEMP_DIR}/IndexController.php" ] && print_msg "success" "IndexController.php ($(stat -f%z "${TEMP_DIR}/IndexController.php" 2>/dev/null || stat -c%s "${TEMP_DIR}/IndexController.php") bytes)"
    
    create_usercontroller
    [ -f "${TEMP_DIR}/UserController.php" ] && print_msg "success" "UserController.php ($(stat -f%z "${TEMP_DIR}/UserController.php" 2>/dev/null || stat -c%s "${TEMP_DIR}/UserController.php") bytes)"
    
    echo ""
    print_msg "info" "Temp directory: ${TEMP_DIR}"
}

backup_files() {
    echo ""
    print_msg "step" "Backup file yang ada..."
    echo ""
    
    mkdir -p "${BACKUP_PATH}/${TIMESTAMP}"
    
    local backed_up=0
    local files=(
        "Http/Controllers/Api/Client/Servers/ServerController.php"
        "Http/Controllers/Admin/ServersController.php"
        "Http/Controllers/Admin/NestController.php"
        "Http/Controllers/Admin/NodeController.php"
        "Http/Controllers/Admin/Settings/IndexController.php"
        "Http/Controllers/Admin/UserController.php"
    )
    
    for file_path in "${files[@]}"; do
        local src="${APP_PATH}/${file_path}"
        local filename=$(basename "$file_path")
        
        if [ -f "$src" ]; then
            cp "$src" "${BACKUP_PATH}/${TIMESTAMP}/${filename}"
            print_msg "success" "Backup: ${filename}"
            ((backed_up++))
        fi
    done
    
    [ $backed_up -gt 0 ] && print_msg "success" "Backup: ${BACKUP_PATH}/${TIMESTAMP}"
}

install_controllers() {
    echo ""
    print_msg "step" "Menginstal controller..."
    echo ""
    
    local installed=0
    
    # ServerController.php
    if [ -f "${TEMP_DIR}/ServerController.php" ]; then
        local dest="${APP_PATH}/Http/Controllers/Api/Client/Servers/ServerController.php"
        mkdir -p "$(dirname "$dest")"
        
        echo -n "   [1/7] ServerController.php ... "
        if cp -f "${TEMP_DIR}/ServerController.php" "$dest" 2>/dev/null; then
            chown www-data:www-data "$dest" 2>/dev/null || chown apache:apache "$dest" 2>/dev/null
            chmod 644 "$dest"
            echo -e "${GREEN}OK${NC}"
            ((installed++))
        else
            echo -e "${RED}FAILED${NC}"
            print_msg "error" "Gagal: $dest"
        fi
    fi
    
    # ServersController.php
    if [ -f "${TEMP_DIR}/ServersController.php" ]; then
        local dest="${APP_PATH}/Http/Controllers/Admin/ServersController.php"
        mkdir -p "$(dirname "$dest")"
        
        echo -n "   [2/7] ServersController.php ... "
        if cp -f "${TEMP_DIR}/ServersController.php" "$dest" 2>/dev/null; then
            chown www-data:www-data "$dest" 2>/dev/null || chown apache:apache "$dest" 2>/dev/null
            chmod 644 "$dest"
            echo -e "${GREEN}OK${NC}"
            ((installed++))
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi
    
    # NestController.php
    if [ -f "${TEMP_DIR}/NestController.php" ]; then
        local dest="${APP_PATH}/Http/Controllers/Admin/NestController.php"
        mkdir -p "$(dirname "$dest")"
        
        echo -n "   [3/7] NestController.php ... "
        if cp -f "${TEMP_DIR}/NestController.php" "$dest" 2>/dev/null; then
            chown www-data:www-data "$dest" 2>/dev/null || chown apache:apache "$dest" 2>/dev/null
            chmod 644 "$dest"
            echo -e "${GREEN}OK${NC}"
            ((installed++))
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi
    
   
    # NodeController.php
    if [ -f "${TEMP_DIR}/NodeController.php" ]; then
        local dest="${APP_PATH}/Http/Controllers/Admin/NodeController.php"
        mkdir -p "$(dirname "$dest")"
        
        echo -n "   [5/7] NodeController.php ... "
        if cp -f "${TEMP_DIR}/NodeController.php" "$dest" 2>/dev/null; then
            chown www-data:www-data "$dest" 2>/dev/null || chown apache:apache "$dest" 2>/dev/null
            chmod 644 "$dest"
            echo -e "${GREEN}OK${NC}"
            ((installed++))
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi
    
    # IndexController.php
    if [ -f "${TEMP_DIR}/IndexController.php" ]; then
        local dest="${APP_PATH}/Http/Controllers/Admin/Settings/IndexController.php"
        mkdir -p "$(dirname "$dest")"
        
        echo -n "   [6/7] IndexController.php ... "
        if cp -f "${TEMP_DIR}/IndexController.php" "$dest" 2>/dev/null; then
            chown www-data:www-data "$dest" 2>/dev/null || chown apache:apache "$dest" 2>/dev/null
            chmod 644 "$dest"
            echo -e "${GREEN}OK${NC}"
            ((installed++))
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi
    
    # UserController.php
    if [ -f "${TEMP_DIR}/UserController.php" ]; then
        local dest="${APP_PATH}/Http/Controllers/Admin/UserController.php"
        mkdir -p "$(dirname "$dest")"
        
        echo -n "   [7/7] UserController.php ... "
        if cp -f "${TEMP_DIR}/UserController.php" "$dest" 2>/dev/null; then
            chown www-data:www-data "$dest" 2>/dev/null || chown apache:apache "$dest" 2>/dev/null
            chmod 644 "$dest"
            echo -e "${GREEN}OK${NC}"
            ((installed++))
        else
            echo -e "${RED}FAILED${NC}"
        fi
    fi
    
    echo ""
    print_msg "success" "Terinstall: ${installed}/7 file"
    
    # Verify installation
    echo ""
    print_msg "step" "Verifikasi instalasi..."
    echo ""
    
    [ -f "${APP_PATH}/Http/Controllers/Api/Client/Servers/ServerController.php" ] && print_msg "success" "ServerController.php TERVERIFIKASI" || print_msg "error" "ServerController.php TIDAK DITEMUKAN"
    [ -f "${APP_PATH}/Http/Controllers/Admin/ServersController.php" ] && print_msg "success" "ServersController.php TERVERIFIKASI" || print_msg "error" "ServersController.php TIDAK DITEMUKAN"
    [ -f "${APP_PATH}/Http/Controllers/Admin/NestController.php" ] && print_msg "success" "NestController.php TERVERIFIKASI" || print_msg "error" "NestController.php TIDAK DITEMUKAN"
    [ -f "${APP_PATH}/Http/Controllers/Admin/NodeController.php" ] && print_msg "success" "NodeController.php TERVERIFIKASI" || print_msg "error" "NodeController.php TIDAK DITEMUKAN"
    [ -f "${APP_PATH}/Http/Controllers/Admin/Settings/IndexController.php" ] && print_msg "success" "IndexController.php TERVERIFIKASI" || print_msg "error" "IndexController.php TIDAK DITEMUKAN"
    [ -f "${APP_PATH}/Http/Controllers/Admin/UserController.php" ] && print_msg "success" "UserController.php TERVERIFIKASI" || print_msg "error" "UserController.php TIDAK DITEMUKAN"
}

clear_cache() {
    echo ""
    print_msg "step" "Clear cache..."
    
    cd "$PTERODACTYL_PATH" || exit
    
    php artisan cache:clear &>/dev/null && print_msg "success" "Cache cleared" || print_msg "warning" "Cache clear failed"
    php artisan config:clear &>/dev/null && print_msg "success" "Config cleared" || print_msg "warning" "Config clear failed"
    php artisan view:clear &>/dev/null && print_msg "success" "View cleared" || print_msg "warning" "View clear failed"
}

show_menu() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════${NC}"
    echo -e "   ${CYAN}[1]${NC} Install Controllers"
    echo -e "   ${CYAN}[2]${NC} Backup Only"
    echo -e "   ${CYAN}[3]${NC} Clear Cache"
    echo -e "   ${CYAN}[0]${NC} Keluar"
    echo -e "${BOLD}════════════════════════════════════════${NC}"
    echo ""
}

main() {
    trap cleanup EXIT
    
    check_root
    show_banner
    verify_pterodactyl
    
    while true; do
        show_menu
        read -p "$(echo -e ${YELLOW}Pilih [0-3]: ${NC})" choice
        
        case $choice in
            1)
                prepare_files
                backup_files
                install_controllers
                clear_cache
                echo ""
                read -p "Tekan Enter..."
                show_banner
                ;;
            2)
                backup_files
                read -p "Tekan Enter..."
                show_banner
                ;;
            3)
                clear_cache
                read -p "Tekan Enter..."
                show_banner
                ;;
            0)
                exit 0
                ;;
            *)
                print_msg "error" "Invalid"
                sleep 1
                show_banner
                ;;
        esac
    done
}

main