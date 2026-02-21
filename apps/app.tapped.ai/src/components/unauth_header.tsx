"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Globe2, Home, Moon, Sun } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useTheme } from "next-themes";
import { Suspense } from "react";
import { LoadingSpinner } from "./LoadingSpinner";
import SearchBar from "./search/SearchBar";
import { Avatar, AvatarFallback, AvatarImage } from "./ui/avatar";
import { Button } from "./ui/button";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuTrigger,
} from "./ui/dropdown-menu";

const queryClient = new QueryClient();

function UnauthHeaderUi({ showSearch = true }: { showSearch?: boolean }) {
	const { setTheme } = useTheme();
	const router = useRouter();

	return (
		<div className="flex w-screen flex-row items-center gap-3 light:bg-background/60 px-4 py-2 backdrop-blur light:supports-backdrop-blur:bg-background/40 dark:bg-background/95 dark:supports-backdrop-blur:bg-background/60">
			<div className="hidden h-full items-center justify-center md:flex">
				<Avatar className="mr-2 bg-background hover:cursor-pointer hover:shadow-xl">
					<AvatarImage
						src="/images/icon_1024.png"
						style={{ objectFit: "cover", overflow: "hidden" }}
						onClick={() => router.push("/")}
					/>
					<AvatarFallback>
						<Home className="h-4 w-4" />
					</AvatarFallback>
				</Avatar>
			</div>
			<div className="flex-1">
				{showSearch && (
					<div className="md:w-3/4 lg:w-3/4 xl:w-1/2">
						<Suspense
							fallback={
								<div className="flex items-center justify-center">
									<LoadingSpinner />
								</div>
							}
						>
							<SearchBar />
						</Suspense>
					</div>
				)}
			</div>
			<div className="flex flex-row gap-3">
				<Link href="/map">
					<Button variant={"secondary"}>
						view the map{" "}
						<span className="ml-2">
							<Globe2 className="h-4 w-4" />
						</span>
					</Button>
				</Link>
				<DropdownMenu>
					<DropdownMenuTrigger asChild>
						<Button variant="ghost" size="icon">
							<Sun className="h-[1.2rem] w-[1.2rem] rotate-0 scale-100 transition-all dark:-rotate-90 dark:scale-0" />
							<Moon className="absolute h-[1.2rem] w-[1.2rem] rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100" />
							<span className="sr-only">Toggle theme</span>
						</Button>
					</DropdownMenuTrigger>
					<DropdownMenuContent align="end">
						<DropdownMenuItem onClick={() => setTheme("light")}>Light</DropdownMenuItem>
						<DropdownMenuItem onClick={() => setTheme("dark")}>Dark</DropdownMenuItem>
						<DropdownMenuItem onClick={() => setTheme("system")}>System</DropdownMenuItem>
					</DropdownMenuContent>
				</DropdownMenu>
			</div>
		</div>
	);
}

export default function UnauthHeader(props: { showSearch?: boolean }) {
	return (
		<QueryClientProvider client={queryClient}>
			<UnauthHeaderUi {...props} />
		</QueryClientProvider>
	);
}
