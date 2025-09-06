'use client';

import { logout } from "@/utils/auth";
import Link from "next/link";
import { useRouter } from "next/navigation";

export default function SignUp() {
    const router = useRouter();
    const onLogout = async () => {
        await logout();
        router.push("/login");
    }

    return (
        <>
            <div className="min-h-screen flex flex-col justify-center items-center">
                <p className="text-center">
                    you must be a subsriber to the label to create an EPK. 
                </p> 
                <p>
                    apply to join our record label
                </p>
                <div className="h-4" />
                <Link
                    href="https://tapped.ai"
                    className='bg-blue-700 text-white font-extrabold px-4 py-2 rounded-full'
                >
                    sign up
                </Link>
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