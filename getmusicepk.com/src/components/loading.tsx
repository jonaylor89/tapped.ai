import { logout } from "@/utils/auth";
import { useRouter } from "next/navigation";

export default function Loading() {
    const router = useRouter();
    const onLogout = async () => {
        await logout();
        router.push("/login");
    }

    return (
        <>
            <div className="min-h-screen flex flex-col justify-center items-center">
                <p>loading...</p>
                <div className="h-4" />
                <button
                    onClick={onLogout}
                    className='text-gray-500 px-4 py-2'
                >
                    logout
                </button>
            </div>
        </>
    );
}